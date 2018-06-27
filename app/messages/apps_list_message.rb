require 'messages/list_message'

module CloudController
  class AppsListMessage < ListMessage
    register_allowed_keys [:names, :guids, :organization_guids, :space_guids, :page, :per_page, :order_by, :order_direction, :include]

    validates_with NoAdditionalParamsValidator
    validates_with IncludeParamValidator, valid_values: ['space']

    validates :names, array: true, allow_nil: true
    validates :guids, array: true, allow_nil: true
    validates :organization_guids, array: true, allow_nil: true
    validates :space_guids, array: true, allow_nil: true

    def to_param_hash
      super(exclude: [:page, :per_page, :order_by])
    end

    def self.from_params(params)
      opts = params.dup
      %w(names guids organization_guids space_guids).each do |attribute|
        to_array! opts, attribute
      end
      new(opts.symbolize_keys)
    end

    def valid_order_by_values
      super << :name
    end
  end
end
