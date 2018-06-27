module CloudController
  class ManifestStrategy
    NULL_START_COMMANDS = ['default', 'null'].freeze

    def initialize(message, process)
      @process = process
      @message = message
    end

    def updated_command
      if NULL_START_COMMANDS.include?(@message.command)
        @process.detected_start_command
      elsif @message.command
        @message.command
      end
    end
  end
end
