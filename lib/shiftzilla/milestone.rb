module Shiftzilla
  class Milestone
    def initialize(mtxt)
      @date  = nil
      @stamp = ''
      unless (mtxt.nil? or mtxt == '')
        @date  = Date.parse(mtxt)
        @stamp = mtxt
      end
    end

    def date
      @date
    end

    def stamp
      @stamp
    end
  end
end
