module Shiftzilla
  class Group
    attr_reader :id, :lead

    def initialize(ginfo)
      @id    = ginfo['id']
      @lead  = ginfo['lead']
    end
  end
end