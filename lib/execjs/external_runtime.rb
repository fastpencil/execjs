require "shellwords"
require "tempfile"
require "execjs/runtime"

module ExecJS
  class ExternalRuntime < Runtime
    class Context < Runtime::Context
      def initialize(runtime, source = "")
        source = encode(source)

        @runtime = runtime
        @source  = source
      end

      def eval(source, options = {})
        source = encode(source)

        if /\S/ =~ source
          exec("return eval(#{JSON.encode("(#{source})")})")
        end
      end

      def exec(source, options = {})
        source = encode(source)
        source = "#{@source}\n#{source}" if @source

        compile_to_tempfile(source) do |file|
          extract_result(@runtime.send(:exec_runtime, file.path))
        end
      end

      def call(identifier, *args)
        eval "#{identifier}.apply(this, #{JSON.encode(args)})"
      end

      protected
        def compile_to_tempfile(source)
          tempfile = Tempfile.open(['execjs', '.js'], @tmpdir)
          tempfile.write compile(source)
          tempfile.close
          yield tempfile
        ensure
          tempfile.close!
        end

        def compile(source)
          @runtime.send(:runner_source).dup.tap do |output|
            output.sub!('#{source}') do
              source
            end
            output.sub!('#{encoded_source}') do
              encoded_source = encode_unicode_codepoints(source)
              JSON.encode("(function(){ #{encoded_source} })()")
            end
            output.sub!('#{json2_source}') do
              IO.read(ExecJS.root + "/support/json2.js")
            end
          end
        end

        def extract_result(output)
          status, value = output.empty? ? [] : JSON.decode(output)
          if status == "ok"
            value
          elsif value =~ /SyntaxError:/
            raise RuntimeError, value
          else
            raise ProgramError, value
          end
        end

        if "".respond_to?(:codepoints)
          def encode_unicode_codepoints(str)
            str.gsub(/[\u0080-\uffff]/) do |ch|
              "\\u%04x" % ch.codepoints.to_a
            end
          end
        else
          def encode_unicode_codepoints(str)
            str.gsub(/([\xC0-\xDF][\x80-\xBF]|
                       [\xE0-\xEF][\x80-\xBF]{2}|
                       [\xF0-\xF7][\x80-\xBF]{3})+/nx) do |ch|
              "\\u%04x" % ch.unpack("U*")
            end
          end
        end
    end

    attr_reader :name

    def initialize(options)
      @name        = options[:name]
      @command     = options[:command]
      @runner_path = options[:runner_path]
      @test_args   = options[:test_args]
      @test_match  = options[:test_match]
      @encoding    = options[:encoding]
      @deprecated  = !!options[:deprecated]
      @binary      = '/usr/local/bin/node'
      @tmpdir      = File.directory?('/mnt/fp2') ? '/mnt/fp2' : '/tmp/fp2'
    end

    def available?
      require "execjs/json"
      true
    end

    def deprecated?
      @deprecated
    end

    protected
      def runner_source
        @runner_source ||= IO.read(@runner_path)
      end

      def exec_runtime(filename)
        output = sh("/usr/local/bin/node #{filename} 2>&1")
        if $?.success?
          output
        else
          raise RuntimeError, output
        end
      end

      def sh(command)
        output, options = nil, {}
        options[:external_encoding] = @encoding if @encoding
        options[:internal_encoding] = ::Encoding.default_internal || 'UTF-8'
        IO.popen(command, options) { |f| output = f.read }
        output
      end

  end
end
