class BoshErrandEnvironment
  def initialize(config)
    @config = config

    CloudController::StenoConfigurer.new(config.get(:logging)).configure do |steno_config_hash|
      steno_config_hash[:sinks] << Steno::Sink::IO.new(STDOUT)
    end
  end

  def setup_environment
    CloudController::DB.load_models(@config.get(:db), Steno.logger('cc.errand'))
    @config.configure_components

    yield if block_given?
  end
end
