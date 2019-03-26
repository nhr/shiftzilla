module Shiftzilla
  class Group
    attr_reader :name, :id, :lead, :components

    def initialize(ginfo)
      @name        = "Group " + ginfo['id']
      @id          = ginfo['id']
      @lead        = ginfo['lead']
      @components  = []
    end

    def set_components(component_list)
      @components += component_list
    end

  end
end
