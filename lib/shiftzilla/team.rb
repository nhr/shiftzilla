module Shiftzilla
  class Team
    attr_reader :name, :lead, :group, :components

    def initialize(tinfo,group_map,ad_hoc=false)
      @name       = tinfo['name']
      @lead       = ad_hoc ? nil : tinfo['lead']
      @group      = ad_hoc ? nil : group_map[tinfo['group']]
      @components = tinfo.has_key?('components') ? tinfo['components'] : []
      @ad_hoc     = ad_hoc
    end

    def ad_hoc?
      @ad_hoc
    end
  end
end
