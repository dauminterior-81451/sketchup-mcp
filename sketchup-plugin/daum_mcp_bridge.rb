require 'json'
require 'socket'
require 'fileutils'
require 'sketchup.rb'

module DaumInterior
  module McpBridge
    HOST = '127.0.0.1'
    PORT = 8765

    @server = nil
    @server_thread = nil
    @jobs = Queue.new
    @results = {}
    @running = false
    @timer_id = nil

    class << self
      def start
        return if @running

        @server = TCPServer.new(HOST, PORT)
        @running = true
        start_worker
        start_timer
        UI.messagebox("Daum MCP Bridge started on http://#{HOST}:#{PORT}")
      rescue Errno::EADDRINUSE
        UI.messagebox("Daum MCP Bridge port #{PORT} is already in use.")
      rescue StandardError => e
        UI.messagebox("Daum MCP Bridge failed: #{e.message}")
      end

      def stop
        @running = false
        @server.close if @server && !@server.closed?
        @server = nil
        @server_thread = nil
        UI.stop_timer(@timer_id) if @timer_id
        @timer_id = nil
        UI.messagebox('Daum MCP Bridge stopped.')
      rescue StandardError => e
        UI.messagebox("Daum MCP Bridge stop failed: #{e.message}")
      end

      def status_message
        state = @running ? 'running' : 'stopped'
        UI.messagebox("Daum MCP Bridge is #{state}.\nURL: http://#{HOST}:#{PORT}")
      end

      def reload_plugin
        stop_without_message
        load(__FILE__)
        start
      rescue StandardError => e
        UI.messagebox("Daum MCP Bridge reload failed: #{e.message}")
      end

      private

      def stop_without_message
        @running = false
        @server.close if @server && !@server.closed?
        @server = nil
        @server_thread = nil
        UI.stop_timer(@timer_id) if @timer_id
        @timer_id = nil
      end

      def start_worker
        @server_thread = Thread.new do
          while @running
            begin
              client = @server.accept
              Thread.new(client) { |socket| handle_client(socket) }
            rescue IOError
              break
            rescue StandardError
              next
            end
          end
        end
      end

      def start_timer
        @timer_id = UI.start_timer(0.1, true) { process_jobs }
      end

      def process_jobs
        until @jobs.empty?
          job = @jobs.pop(true)
          @results[job[:id]] = begin
            { ok: true, data: route(job[:method], job[:path], job[:body]) }
          rescue StandardError => e
            { ok: false, error: e.message }
          end
        end
      rescue ThreadError
        nil
      end

      def handle_client(socket)
        begin
          request = read_request(socket)
          method = request[:method]
          path = request[:path]
          body = request[:body]

          job_id = "#{Time.now.to_f}-#{rand(100000)}"
          @jobs << { id: job_id, method: method, path: path, body: body }

          started_at = Time.now
          sleep(0.02) until @results.key?(job_id) || Time.now - started_at > 5
          result = @results.delete(job_id)

          if result.nil?
            write_response(socket, 504, { error: 'SketchUp bridge job timed out.' })
          elsif result[:ok]
            write_response(socket, 200, result[:data])
          else
            write_response(socket, 500, { error: result[:error] })
          end
        rescue StandardError => e
          write_response(socket, 500, { error: e.message })
        end
      ensure
        socket.close if socket && !socket.closed?
      end

      def read_request(socket)
        first_line = socket.gets.to_s.strip
        method, path = first_line.split(' ')
        headers = {}

        while (line = socket.gets)
          line = line.strip
          break if line.empty?
          key, value = line.split(':', 2)
          headers[key.downcase] = value.strip if key && value
        end

        length = headers['content-length'].to_i
        raw_body = length.positive? ? socket.read(length).to_s : ''
        body = raw_body.empty? ? {} : JSON.parse(raw_body)

        { method: method, path: path, body: body }
      end

      def write_response(socket, status, payload)
        body = JSON.generate(payload).encode('UTF-8')
        reason = status == 200 ? 'OK' : 'ERROR'
        socket.write("HTTP/1.1 #{status} #{reason}\r\n")
        socket.write("Content-Type: application/json; charset=utf-8\r\n")
        socket.write("Content-Length: #{body.bytesize}\r\n")
        socket.write("Connection: close\r\n\r\n")
        socket.write(body)
      end

      def route(method, path, body)
        return { pong: true } if method == 'GET' && path == '/ping'
        return bridge_status if method == 'GET' && path == '/status'
        return model_summary if method == 'GET' && path == '/model_summary'
        return selection_summary if method == 'GET' && path == '/selection'
        return rename_selection(body['name'].to_s) if method == 'POST' && path == '/rename_selection'
        return export_top_view(body) if method == 'POST' && path == '/export_top_view'

        raise "Unknown endpoint: #{method} #{path}"
      end

      def bridge_status
        {
          running: @running,
          host: HOST,
          port: PORT,
          sketchup_version: Sketchup.version
        }
      end

      def model_summary
        model = Sketchup.active_model
        entities = model.entities.to_a
        definitions = model.definitions.to_a.reject(&:image?)

        {
          title: model.title,
          path: model.path,
          units: length_unit_name(model),
          entities_count: entities.length,
          groups_count: entities.count { |entity| entity.is_a?(Sketchup::Group) },
          component_instances_count: entities.count { |entity| entity.is_a?(Sketchup::ComponentInstance) },
          component_definitions_count: definitions.length,
          materials_count: model.materials.length,
          tags_count: model.layers.length
        }
      end

      def selection_summary
        model = Sketchup.active_model
        items = model.selection.to_a.map { |entity| entity_summary(entity) }

        {
          count: items.length,
          items: items
        }
      end

      def rename_selection(name)
        raise 'Name is required.' if name.strip.empty?

        changed = 0
        Sketchup.active_model.selection.each do |entity|
          next unless entity.respond_to?(:name=)
          entity.name = name
          changed += 1
        end

        { changed: changed, name: name }
      end

      def export_top_view(body)
        output_path = body['outputPath'].to_s
        raise 'outputPath is required.' if output_path.strip.empty?

        width = positive_integer(body['width'], 1600)
        height = positive_integer(body['height'], 1200)
        model = Sketchup.active_model
        view = model.active_view
        bounds = model.bounds
        center = bounds.center
        distance = [bounds.width, bounds.depth, bounds.height, 1000.mm].max * 2

        eye = Geom::Point3d.new(center.x, center.y, center.z + distance)
        target = Geom::Point3d.new(center.x, center.y, center.z)
        up = Geom::Vector3d.new(0, 1, 0)
        camera = Sketchup::Camera.new(eye, target, up)
        camera.perspective = false

        view.camera = camera
        view.zoom_extents
        view.refresh

        FileUtils.mkdir_p(File.dirname(output_path))
        ok = view.write_image(
          filename: output_path,
          width: width,
          height: height,
          antialias: true,
          compression: 0.9,
          transparent: false
        )
        raise "Failed to write image: #{output_path}" unless ok

        {
          output_path: output_path,
          width: width,
          height: height,
          title: model.title
        }
      end

      def entity_summary(entity)
        bounds = entity.respond_to?(:bounds) ? entity.bounds : nil
        {
          type: entity.typename,
          name: entity.respond_to?(:name) ? entity.name.to_s : '',
          layer: entity.respond_to?(:layer) && entity.layer ? entity.layer.name : '',
          bounds_mm: bounds ? bounds_summary(bounds) : nil
        }
      end

      def bounds_summary(bounds)
        {
          width: bounds.width.to_mm.round(2),
          depth: bounds.depth.to_mm.round(2),
          height: bounds.height.to_mm.round(2)
        }
      end

      def positive_integer(value, fallback)
        integer = value.to_i
        integer.positive? ? integer : fallback
      end

      def length_unit_name(model)
        unit = model.options['UnitsOptions']['LengthUnit']
        {
          0 => 'inches',
          1 => 'feet',
          2 => 'millimeters',
          3 => 'centimeters',
          4 => 'meters'
        }[unit] || unit.to_s
      end
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('Daum MCP Bridge')
      menu.add_item('Start Bridge') { start }
      menu.add_item('Status') { status_message }
      menu.add_item('Stop Bridge') { stop }
      menu.add_separator
      menu.add_item('Reload Plugin') { reload_plugin }
      file_loaded(__FILE__)
    end
  end
end
