module Shiftzilla
  class Team
    attr_reader :name, :lead, :group, :components

    def initialize(tinfo,group_map)
      @name       = tinfo['name']
      @lead       = tinfo['lead']
      @group      = group_map[tinfo['group']]
      @components = tinfo.has_key?('components') ? tinfo['components'] : []
    end
  end
end
