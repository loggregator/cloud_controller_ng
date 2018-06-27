require 'messages/base_message'

module CloudController
  class ProcessScaleMessage < BaseMessage
    register_allowed_keys [:instances, :memory_in_mb, :disk_in_mb]

    validates_with NoAdditionalKeysValidator

    validates :instances, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :memory_in_mb, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :disk_in_mb, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  end
end
