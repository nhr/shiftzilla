require 'shiftzilla/milestone'

module Shiftzilla
  class Milestones
    def initialize(msrc)
      @milestones = {}
      msrc.each do |key,val|
        @milestones[key.to_sym] = Shiftzilla::Milestone.new(val)
      end
    end

    def start
      @milestones[:start]
    end

    def feature_complete
      @milestones[:feature_complete]
    end

    def code_freeze
      @milestones[:code_freeze]
    end

    def ga
      @milestones[:ga]
    end
  end
end
