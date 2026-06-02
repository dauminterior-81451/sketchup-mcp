require 'json'
require 'socket'
require 'fileutils'
require 'time'
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
        return analyze_selection if method == 'GET' && path == '/analyze_selection'
        return find_cleanup_targets(body) if method == 'POST' && path == '/find_cleanup_targets'
        return rename_selection(body['name'].to_s) if method == 'POST' && path == '/rename_selection'
        return export_top_view(body) if method == 'POST' && path == '/export_top_view'
        return export_current_view(body) if method == 'POST' && path == '/export_current_view'
        return export_selection_view(body) if method == 'POST' && path == '/export_selection_view'
        return create_box(body) if method == 'POST' && path == '/create_box'
        return create_wall(body) if method == 'POST' && path == '/create_wall'
        return move_selection(body) if method == 'POST' && path == '/move_selection'
        return rotate_selection(body) if method == 'POST' && path == '/rotate_selection'
        return hide_selection if method == 'POST' && path == '/hide_selection'
        return show_all if method == 'POST' && path == '/show_all'
        return save_current_view(body) if method == 'POST' && path == '/save_current_view'
        return create_scene(body) if method == 'POST' && path == '/create_scene'
        return auto_name_selection(body) if method == 'POST' && path == '/auto_name_selection'
        return backup_model if method == 'POST' && path == '/backup_model'
        return measure_selection if method == 'GET' && path == '/measure_selection'
        return add_dimensions_to_selection(body) if method == 'POST' && path == '/add_dimensions_to_selection'
        return create_or_assign_tag(body) if method == 'POST' && path == '/create_or_assign_tag'
        return apply_material_to_selection(body) if method == 'POST' && path == '/apply_material_to_selection'
        return align_selection(body) if method == 'POST' && path == '/align_selection'

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

      def export_selection_view(body)
        output_path = body['outputPath'].to_s
        raise 'outputPath is required.' if output_path.strip.empty?

        width = positive_integer(body['width'], 1600)
        height = positive_integer(body['height'], 1200)
        margin = positive_float(body['margin'], 1.15)
        model = Sketchup.active_model
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        bounds = selection_bounds(selection)
        view = model.active_view
        center = bounds.center
        distance = [bounds.width, bounds.depth, bounds.height, 1000.mm].max * 2
        image_aspect = width.to_f / height.to_f
        view_height = [bounds.depth, bounds.width / image_aspect].max * margin

        camera = Sketchup::Camera.new(
          Geom::Point3d.new(center.x, center.y, center.z + distance),
          Geom::Point3d.new(center.x, center.y, center.z),
          Geom::Vector3d.new(0, 1, 0)
        )
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
          selection_count: selection.length,
          bounds_mm: bounds_summary(bounds)
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

      def save_current_view(body)
        create_scene(body)
      end

      def create_scene(body)
        name = body['name'].to_s.strip
        raise 'name is required.' if name.empty?

        model = Sketchup.active_model
        model.start_operation("Create Scene #{name}", true)
        page = model.pages.add(name)
        page.use_camera = true
        page.camera = model.active_view.camera
        page.use_rendering_options = true
        page.use_shadow_info = true
        model.pages.selected_page = page
        model.commit_operation
        log_action('create_scene', { name: name })

        { created: true, name: page.name, pages_count: model.pages.length }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def auto_name_selection(body)
        prefix = body['prefix'].to_s.strip
        raise 'prefix is required.' if prefix.empty?

        overwrite = body['overwrite'] == true
        model = Sketchup.active_model
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        changed = []
        model.start_operation('Auto Name Selection', true)
        selection.each_with_index do |entity, index|
          next unless entity.respond_to?(:name=)
          next if !overwrite && entity.respond_to?(:name) && !entity.name.to_s.strip.empty?

          new_name = "#{prefix}_#{format('%03d', index + 1)}"
          entity.name = new_name
          changed << { type: entity.typename, name: new_name }
        end
        model.commit_operation
        log_action('auto_name_selection', { prefix: prefix, overwrite: overwrite, changed: changed.length })

        { changed: changed.length, items: changed }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def backup_model
        model = Sketchup.active_model
        raise 'Model must be saved before backup.' if model.path.to_s.strip.empty?

        backup_dir = File.join(File.dirname(model.path), 'codex-backups')
        FileUtils.mkdir_p(backup_dir)
        base_name = File.basename(model.path, '.skp')
        timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
        backup_path = File.join(backup_dir, "#{base_name}-#{timestamp}.skp")
        model.save_copy(backup_path)
        log_action('backup_model', { backup_path: backup_path })

        {
          created: true,
          backup_path: backup_path,
          model_path: model.path
        }
      end

      def measure_selection
        analyze_selection
      end

      def add_dimensions_to_selection(body)
        offset = positive_float(body['offsetMm'], 300).mm
        model = Sketchup.active_model
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        bounds = selection_bounds(selection)
        model.start_operation('Add Selection Dimensions', true)
        entities = model.active_entities
        created = 0

        x1 = Geom::Point3d.new(bounds.min.x, bounds.min.y - offset, bounds.min.z)
        x2 = Geom::Point3d.new(bounds.max.x, bounds.min.y - offset, bounds.min.z)
        entities.add_dimension_linear(x1, x2, Geom::Vector3d.new(0, -offset, 0))
        created += 1

        y1 = Geom::Point3d.new(bounds.max.x + offset, bounds.min.y, bounds.min.z)
        y2 = Geom::Point3d.new(bounds.max.x + offset, bounds.max.y, bounds.min.z)
        entities.add_dimension_linear(y1, y2, Geom::Vector3d.new(offset, 0, 0))
        created += 1

        if bounds.height > 0
          z1 = Geom::Point3d.new(bounds.max.x + offset, bounds.max.y + offset, bounds.min.z)
          z2 = Geom::Point3d.new(bounds.max.x + offset, bounds.max.y + offset, bounds.max.z)
          entities.add_dimension_linear(z1, z2, Geom::Vector3d.new(offset, offset, 0))
          created += 1
        end

        model.commit_operation
        log_action('add_dimensions_to_selection', { count: created, offset_mm: offset.to_mm.round(2) })

        { created: created, bounds_mm: bounds_summary(bounds) }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def create_or_assign_tag(body)
        tag_name = body['tagName'].to_s.strip
        raise 'tagName is required.' if tag_name.empty?

        model = Sketchup.active_model
        layer = model.layers[tag_name] || model.layers.add(tag_name)
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        model.start_operation("Assign Tag #{tag_name}", true)
        selection.each { |entity| entity.layer = layer if entity.respond_to?(:layer=) }
        model.commit_operation
        log_action('create_or_assign_tag', { tag_name: tag_name, count: selection.length })

        { assigned: selection.length, tag_name: tag_name }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def apply_material_to_selection(body)
        name = body['name'].to_s.strip
        color = body['color'].to_s.strip
        raise 'name is required.' if name.empty?
        raise 'color is required.' if color.empty?

        model = Sketchup.active_model
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        material = model.materials[name] || model.materials.add(name)
        material.color = parse_color(color)

        model.start_operation("Apply Material #{name}", true)
        selection.each do |entity|
          entity.material = material if entity.respond_to?(:material=)
        end
        model.commit_operation
        log_action('apply_material_to_selection', { name: name, color: color, count: selection.length })

        { applied: selection.length, material: name, color: color }
      rescue StandardError
        Sketchup.active_model.abort_operation
        raise
      end

      def align_selection(body)
        axis = body['axis'].to_s.downcase
        mode = body['mode'].to_s.downcase
        value = required_number(body, 'valueMm').mm
        axis_index = { 'x' => 0, 'y' => 1, 'z' => 2 }[axis]
        raise 'axis must be x, y, or z.' if axis_index.nil?
        raise 'mode must be min, center, or max.' unless %w[min center max].include?(mode)

        model = Sketchup.active_model
        selection = model.selection.to_a
        raise 'No selected entities.' if selection.empty?

        model.start_operation('Align Selection', true)
        moved = 0
        selection.each do |entity|
          next unless entity.respond_to?(:bounds)

          current = bounds_axis_value(entity.bounds, axis, mode)
          delta = value - current
          vector = axis_vector(axis, delta)
          transform = Geom::Transformation.translation(vector)
          model.active_entities.transform_entities(transform, [entity])
          moved += 1
        end
        model.commit_operation
        log_action('align_selection', { axis: axis, mode: mode, value_mm: value.to_mm.round(2), moved: moved })

        { moved: moved, axis: axis, mode: mode, value_mm: value.to_mm.round(2) }
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
          material: entity.respond_to?(:material) && entity.material ? entity.material.display_name : '',
          bounds_mm: bounds ? bounds_summary(bounds) : nil
        }
      end

      def analyze_selection
        selection = Sketchup.active_model.selection.to_a
        selection_bounds_value = selection.empty? ? nil : selection_bounds(selection)
        items = selection.map { |entity| selection_analysis_item(entity) }

        {
          count: selection.length,
          combined_bounds_mm: selection_bounds_value ? bounds_summary(selection_bounds_value) : nil,
          combined_area_m2: items.map { |item| item[:area_m2].to_f }.sum.round(3),
          items: items,
          hints: selection_hints(items)
        }
      end

      def selection_analysis_item(entity)
        bounds = entity.respond_to?(:bounds) ? entity.bounds : nil
        entity_area = area_m2(entity)
        {
          type: entity.typename,
          name: entity.respond_to?(:name) ? entity.name.to_s : '',
          layer: entity.respond_to?(:layer) && entity.layer ? entity.layer.name : '',
          material: entity.respond_to?(:material) && entity.material ? entity.material.display_name : '',
          hidden: entity.respond_to?(:hidden?) ? entity.hidden? : false,
          bounds_mm: bounds ? bounds_summary(bounds) : nil,
          center_mm: bounds ? point_summary(bounds.center) : nil,
          area_m2: entity_area,
          cleanup_hints: entity_cleanup_hints(entity, bounds)
        }
      end

      def find_cleanup_targets(body)
        far_distance = positive_float(body['farDistanceMm'], 30000)
        tiny_edge = positive_float(body['tinyEdgeMm'], 5)
        model = Sketchup.active_model
        origin = Geom::Point3d.new(0, 0, 0)
        hidden = []
        unnamed = []
        far = []
        tiny_edges = []
        tagless = []

        model.entities.each do |entity|
          hidden << cleanup_item(entity) if entity.respond_to?(:hidden?) && entity.hidden?
          unnamed << cleanup_item(entity) if unnamed_container?(entity)
          tagless << cleanup_item(entity) if tagless?(entity)

          if entity.respond_to?(:bounds)
            distance_mm = entity.bounds.center.distance(origin).to_mm
            item = cleanup_item(entity)
            item[:distance_from_origin_mm] = distance_mm.round(2)
            far << item if distance_mm > far_distance
          end

          if entity.is_a?(Sketchup::Edge) && entity.length.to_mm < tiny_edge
            item = cleanup_item(entity)
            item[:length_mm] = entity.length.to_mm.round(2)
            tiny_edges << item
          end
        end

        {
          thresholds: {
            far_distance_mm: far_distance,
            tiny_edge_mm: tiny_edge
          },
          hidden_entities: hidden.first(50),
          unnamed_groups_or_components: unnamed.first(50),
          tagless_entities: tagless.first(50),
          far_entities: far.sort_by { |item| -item[:distance_from_origin_mm] }.first(50),
          tiny_edges: tiny_edges.first(50),
          summary: {
            hidden_entities: hidden.length,
            unnamed_groups_or_components: unnamed.length,
            tagless_entities: tagless.length,
            far_entities: far.length,
            tiny_edges: tiny_edges.length
          }
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

      def selection_bounds(selection)
        bounds = Geom::BoundingBox.new
        selection.each { |entity| bounds.add(entity.bounds) if entity.respond_to?(:bounds) }
        raise 'Selected entities have no bounds.' unless bounds.valid?

        bounds
      end

      def area_m2(entity)
        total = 0.0
        if entity.is_a?(Sketchup::Face)
          total += entity.area
        elsif entity.respond_to?(:entities)
          entity.entities.grep(Sketchup::Face).each { |face| total += face.area }
        elsif entity.respond_to?(:definition) && entity.definition
          entity.definition.entities.grep(Sketchup::Face).each { |face| total += face.area }
        end
        (total * 0.00064516).round(3)
      end

      def entity_cleanup_hints(entity, bounds)
        hints = []
        hints << 'name_missing' if unnamed_container?(entity)
        hints << 'tag_missing' if tagless?(entity)
        hints << 'hidden' if entity.respond_to?(:hidden?) && entity.hidden?
        hints << 'tiny_bounds' if bounds && bounds_diagonal_mm(bounds) < 10
        hints
      end

      def selection_hints(items)
        hints = []
        hints << 'nothing_selected' if items.empty?
        hints << 'some_names_missing' if items.any? { |item| item[:cleanup_hints].include?('name_missing') }
        hints << 'some_tags_missing' if items.any? { |item| item[:cleanup_hints].include?('tag_missing') }
        hints << 'tiny_entities_selected' if items.any? { |item| item[:cleanup_hints].include?('tiny_bounds') }
        hints
      end

      def cleanup_item(entity)
        bounds = entity.respond_to?(:bounds) ? entity.bounds : nil
        {
          type: entity.typename,
          name: entity.respond_to?(:name) ? entity.name.to_s : '',
          layer: entity.respond_to?(:layer) && entity.layer ? entity.layer.name : '',
          bounds_mm: bounds ? bounds_summary(bounds) : nil,
          center_mm: bounds ? point_summary(bounds.center) : nil
        }
      end

      def unnamed_container?(entity)
        return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        entity.respond_to?(:name) && entity.name.to_s.strip.empty?
      end

      def tagless?(entity)
        return false unless entity.respond_to?(:layer) && entity.layer

        entity.layer.name.to_s == 'Layer0' || entity.layer.name.to_s == 'Untagged'
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

      def bounds_diagonal_mm(bounds)
        Math.sqrt(bounds.width.to_mm**2 + bounds.depth.to_mm**2 + bounds.height.to_mm**2).round(2)
      end

      def point_summary(point)
        {
          x: point.x.to_mm.round(2),
          y: point.y.to_mm.round(2),
          z: point.z.to_mm.round(2)
        }
      end

      def parse_color(value)
        hex = value.start_with?('#') ? value[1..] : value
        raise 'color must be #RRGGBB.' unless hex && hex.match?(/\A[0-9a-fA-F]{6}\z/)

        Sketchup::Color.new(hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16))
      end

      def bounds_axis_value(bounds, axis, mode)
        case [axis, mode]
        when ['x', 'min'] then bounds.min.x
        when ['x', 'center'] then bounds.center.x
        when ['x', 'max'] then bounds.max.x
        when ['y', 'min'] then bounds.min.y
        when ['y', 'center'] then bounds.center.y
        when ['y', 'max'] then bounds.max.y
        when ['z', 'min'] then bounds.min.z
        when ['z', 'center'] then bounds.center.z
        when ['z', 'max'] then bounds.max.z
        end
      end

      def axis_vector(axis, delta)
        return Geom::Vector3d.new(delta, 0, 0) if axis == 'x'
        return Geom::Vector3d.new(0, delta, 0) if axis == 'y'

        Geom::Vector3d.new(0, 0, delta)
      end

      def log_action(action, payload)
        model = Sketchup.active_model
        base_dir = model.path.to_s.strip.empty? ? Dir.home : File.dirname(model.path)
        log_dir = File.join(base_dir, 'codex-logs')
        FileUtils.mkdir_p(log_dir)
        log_path = File.join(log_dir, 'sketchup-mcp-actions.jsonl')
        event = {
          at: Time.now.iso8601,
          action: action,
          model_title: model.title,
          model_path: model.path,
          payload: payload
        }
        File.open(log_path, 'a:utf-8') { |file| file.puts(JSON.generate(event)) }
        log_path
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
