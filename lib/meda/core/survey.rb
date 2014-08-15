require 'digest'

module Meda

  # Represents a single identified user in the analytics system
  class Survey

    attr_reader :dataset, :attributes

    def initialize(dataset, attributes={})
      @dataset = dataset
      @attributes = attributes
    end

  end
end
