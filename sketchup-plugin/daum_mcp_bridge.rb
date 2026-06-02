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
        return bounds_debug if method == 'GET' && path == '/bounds_debug'
        return rename_selection(body['name'].to_s) if method == 'POST' && path == '/rename_selection'
        return export_top_view(body) if method == 'POST' && path == '/export_top_view'
        return export_current_view(body) if method == 'POST' && path == '/export_current_view'
        return create_box(body) if method == 'POST' && path == '/create_box'
        return create_wall(body) if method == 'POST' && path == '/create_wall'
        return move_selection(body) if method == 'POST' && path == '/move_selection'
        return rotate_selection(body) if method == 'POST' && path == '/rotate_selection'
        return hide_selection if method == 'POST' && path == '/hide_selection'
        return show_all if method == 'POST' && path == '/show_all'

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
        margin = positive_float(body['margin'], 1.15)
        model = Sketchup.active_model
        view = model.active_view
        bounds = visible_model_bounds(model)
        center = bounds.center
        distance = [bounds.width, bounds.depth, bounds.height, 1000.mm].max * 2
        image_aspect = width.to_f / height.to_f
        view_height = [bounds.depth, bounds.width / image_aspect].max * margin

        eye = Geom::Point3d.new(center.x, center.y, center.z + distance)
        target = Geom::Point3d.new(center.x, center.y, center.z)
        up = Geom::Vector3d.new(0, 1, 0)
        camera = Sketchup::Camera.new(eye, target, up)
        camera.perspective = false
        camera.height = view_height

        view.camera = camera
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
          margin: margin,
          title: model.title
        }
      end

      def export_current_view(body)
        output_path = body['outputPath'].to_s
        raise 'outputPath is required.' if output_path.strip.empty?

        width = positive_integer(body['width'], 1600)
        height = positive_integer(body['height'], 1200)
        view = Sketchup.active_model.active_view

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
          title: Sketchup.active_model.title
        }
      end

      def create_box(body)
        width = required_mm(body, 'width')
        depth = required_mm(body, 'depth')
        height = required_mm(body, 'height')
        origin = point_from_body(body)
        name = body['name'].to_s.strip
        name = 'MCP Box' if name.empty?

        model = Sketchup.active_model
        model.start_operation("Create #{name}", true)
        group = model.active_entities.add_group
        entities = group.entities
        pts = [
          origin,
          Geom::Point3d.new(origin.x + width, origin.y, origin.z),
          Geom::Point3d.new(origin.x + width, origin.y + depth, origin.z),
          Geom::Point3d.new(origin.x, origin.y + depth, origin.z)
        ]
        face = entities.add_face(pts)
        face.reverse! if face.normal.z < 0
        face.pushpull(height)
        group.name = name
        model.commit_operation

        {
          created: true,
          type: 'Group',
          name: group.name,
          bounds_mm: bounds_summary(group.bounds)
        }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def create_wall(body)
        x1 = required_number(body, 'x1').mm
        y1 = required_number(body, 'y1').mm
        x2 = required_number(body, 'x2').mm
        y2 = required_number(body, 'y2').mm
        thickness = required_mm(body, 'thickness')
        height = required_mm(body, 'height')
        z = number_or_default(body, 'z', 0).mm
        name = body['name'].to_s.strip
        name = 'MCP Wall' if name.empty?

        start_pt = Geom::Point3d.new(x1, y1, z)
        end_pt = Geom::Point3d.new(x2, y2, z)
        direction = end_pt - start_pt
        raise 'Wall length must be greater than 0.' unless direction.length.positive?

        normal = Geom::Vector3d.new(-direction.y, direction.x, 0)
        normal.length = thickness / 2.0
        normal_reverse = Geom::Vector3d.new(-normal.x, -normal.y, -normal.z)
        pts = [
          start_pt.offset(normal),
          end_pt.offset(normal),
          end_pt.offset(normal_reverse),
          start_pt.offset(normal_reverse)
        ]

        model = Sketchup.active_model
        model.start_operation("Create #{name}", true)
        group = model.active_entities.add_group
        face = group.entities.add_face(pts)
        face.reverse! if face.normal.z < 0
        face.pushpull(height)
        group.name = name
        model.commit_operation

        {
          created: true,
          type: 'Group',
          name: group.name,
          length_mm: direction.length.to_mm.round(2),
          bounds_mm: bounds_summary(group.bounds)
        }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def move_selection(body)
        dx = number_or_default(body, 'dx', 0).mm
        dy = number_or_default(body, 'dy', 0).mm
        dz = number_or_default(body, 'dz', 0).mm
        model = Sketchup.active_model
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        model.start_operation('Move Selection', true)
        transform = Geom::Transformation.translation(Geom::Vector3d.new(dx, dy, dz))
        model.active_entities.transform_entities(transform, selection)
        model.commit_operation

        { moved: selection.length, dx_mm: dx.to_mm, dy_mm: dy.to_mm, dz_mm: dz.to_mm }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def rotate_selection(body)
        axis = body['axis'].to_s.downcase
        angle_degrees = required_number(body, 'angleDegrees')
        vector = {
          'x' => Geom::Vector3d.new(1, 0, 0),
          'y' => Geom::Vector3d.new(0, 1, 0),
          'z' => Geom::Vector3d.new(0, 0, 1)
        }[axis]
        raise 'axis must be x, y, or z.' unless vector

        model = Sketchup.active_model
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        bounds = Geom::BoundingBox.new
        selection.each { |entity| bounds.add(entity.bounds) if entity.respond_to?(:bounds) }
        model.start_operation('Rotate Selection', true)
        transform = Geom::Transformation.rotation(bounds.center, vector, angle_degrees.degrees)
        model.active_entities.transform_entities(transform, selection)
        model.commit_operation

        { rotated: selection.length, axis: axis, angle_degrees: angle_degrees }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def hide_selection
        model = Sketchup.active_model
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        model.start_operation('Hide Selection', true)
        selection.each { |entity| entity.hidden = true if entity.respond_to?(:hidden=) }
        model.commit_operation
        { hidden: selection.length }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def show_all
        model = Sketchup.active_model
        changed = 0
        model.start_operation('Show All Top-Level Entities', true)
        model.entities.each do |entity|
          next unless entity.respond_to?(:hidden=) && entity.hidden?
          entity.hidden = false
          changed += 1
        end
        model.commit_operation
        { shown: changed }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
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

      def visible_model_bounds(model)
        bounds = Geom::BoundingBox.new
        model.entities.each do |entity|
          next unless entity_visible?(entity)
          next unless entity.respond_to?(:bounds)

          bounds.add(entity.bounds)
        end
        raise 'No visible model entities found.' unless bounds.valid?

        bounds
      end

      def bounds_debug
        items = Sketchup.active_model.entities.to_a
          .select { |entity| entity_visible?(entity) && entity.respond_to?(:bounds) }
          .map { |entity| bounds_debug_item(entity) }
          .sort_by { |item| -item[:diagonal_mm] }
          .first(20)

        { count: items.length, items: items }
      end

      def bounds_debug_item(entity)
        bounds = entity.bounds
        {
          type: entity.typename,
          name: entity.respond_to?(:name) ? entity.name.to_s : '',
          layer: entity.respond_to?(:layer) && entity.layer ? entity.layer.name : '',
          width_mm: bounds.width.to_mm.round(2),
          depth_mm: bounds.depth.to_mm.round(2),
          height_mm: bounds.height.to_mm.round(2),
          center_mm: {
            x: bounds.center.x.to_mm.round(2),
            y: bounds.center.y.to_mm.round(2),
            z: bounds.center.z.to_mm.round(2)
          },
          diagonal_mm: Math.sqrt(bounds.width.to_mm**2 + bounds.depth.to_mm**2 + bounds.height.to_mm**2).round(2)
        }
      end

      def entity_visible?(entity)
        return false if entity.respond_to?(:hidden?) && entity.hidden?
        return false if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?

        true
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

      def positive_float(value, fallback)
        float = value.to_f
        float.positive? ? float : fallback
      end

      def point_from_body(body)
        Geom::Point3d.new(
          number_or_default(body, 'x', 0).mm,
          number_or_default(body, 'y', 0).mm,
          number_or_default(body, 'z', 0).mm
        )
      end

      def required_mm(body, key)
        required_positive_number(body, key).mm
      end

      def required_number(body, key)
        value = body[key]
        raise "#{key} is required." if value.nil?

        value.to_f
      end

      def required_positive_number(body, key)
        number = required_number(body, key)
        raise "#{key} must be greater than 0." if number <= 0

        number
      end

      def number_or_default(body, key, fallback)
        value = body[key]
        value.nil? ? fallback : value.to_f
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
