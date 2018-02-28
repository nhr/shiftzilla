require 'shiftzilla/milestone'

module Shiftzilla
  class Milestones
    def initialize(msrc)
      @milestones = {}
      [[:start,           'Start'],
       [:feature_complete,'FeatureComplete'],
       [:code_freeze,     'CodeFreeze'     ],
       [:ga,              'GA'             ]].each do |set|
        key = set[0]
        src = set[1]
        @milestones[key] = Shiftzilla::Milestone.new(msrc[src])
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
