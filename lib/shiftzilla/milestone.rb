require 'date'

module Shiftzilla
  class Milestone
    def initialize(mtxt)
      @date  = nil
      @stamp = ''
      if mtxt.start_with?('today')
        @date = variable_date(mtxt)
        @stamp = @date.strftime('%Y-%m-%d')
      elsif not (mtxt.nil? or mtxt == '')
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

    private

    def variable_date(d)
      # Takes a variable date string and returns the appropriate date object
      # Variable dates of the form today[+,-]#[d,w,m,s]
      today = Date.today

      if d.length < 8
        return today
      end

      operation = d[5]
      val = d[6..-2].to_i
      unit = d[-1]
      days = 0

      # Convert to days for simple addition
      case unit
      when 'd'
        days = val
      when 'w'
        days = 7*val
      when 'm'
        days = 30*val
      when 's'      # Sprints
        days = 21*val
      else
        days = val
      end

      if operation == '-'
        days = days * -1
      end

      return today+days
    end
  end
end
