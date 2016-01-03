module Middleman
  module Sitemap
    module Extensions
      # Class to handle managing ignores
      class Ignores < Extension
        self.resource_list_manipulator_priority = 0

        # Expose `create_ignore` as `app.ignore`
        expose_to_application ignore: :create_ignore

        # Expose `create_ignore` to config as `ignore`
        expose_to_config ignore: :create_ignore

        def initialize(app, config={}, &block)
          super

          # Set of callbacks which can assign ignored status
          @ignored_callbacks = []
        end

        def after_configuration
          ::Middleman::CoreExtensions::Collections::StepContext.add_to_context(:ignore, &method(:create_anonymous_ignore))
        end

        # Ignore a path or add an ignore callback
        # @param [String, Regexp] path Path glob expression, or path regex
        # @return [void]
        Contract Maybe[Or[String, Regexp]], Maybe[Proc] => Any
        def create_ignore(path=nil, &block)
          @ignored_callbacks << create_anonymous_ignore(path, &block)
          @app.sitemap.rebuild_resource_list!(:added_ignore)
          @app.sitemap.invalidate_resources_not_ignored_cache!
        end

        def create_anonymous_ignore(path=nil, &block)
          IgnoreDescriptor.new(path, block)
        end

        # Update the main sitemap resource list
        # @return Array<Middleman::Sitemap::Resource>
        Contract ResourceList => ResourceList
        def manipulate_resource_list(resources)
          @ignored_callbacks.reduce(resources) do |sum, c|
            c.execute_descriptor(app, sum)
          end
        end

        IgnoreDescriptor = Struct.new(:path, :block) do
          def execute_descriptor(app, resources)
            resources.map do |r|
              # Ignore based on the source path (without template extensions)
              if ignored?(r.path)
                r.ignore!
              else
                # This allows files to be ignored by their source file name (with template extensions)
                r.ignore! if !r.is_a?(ProxyResource) && r.file_descriptor && ignored?(r.file_descriptor[:relative_path].to_s)
              end

              r
            end
          end

          def ignored?(match_path)
            match_path = ::Middleman::Util.normalize_path(match_path)

            if path.is_a? Regexp
              match_path =~ path
            elsif path.is_a? String
              path_clean = ::Middleman::Util.normalize_path(path)

              if path_clean.include?('*') # It's a glob
                if defined?(::File::FNM_EXTGLOB)
                  ::File.fnmatch(path_clean, match_path, ::File::FNM_EXTGLOB)
                else
                  ::File.fnmatch(path_clean, match_path)
                end
              else
                match_path == path_clean
              end
            elsif block_given?
              block.call(match_path)
            end
          end
        end
      end
    end
  end
end
