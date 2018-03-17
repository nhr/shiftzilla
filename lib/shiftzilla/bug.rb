module Shiftzilla
  class Bug
    attr_reader :id, :first_seen, :last_seen, :test_blocker, :owner, :component, :pm_score, :cust_cases

    def initialize(bzid,binfo)
      @id           = bzid
      @first_seen   = binfo[:snapdate]
      @last_seen    = binfo[:snapdate]
      @test_blocker = binfo[:test_blocker]
      @owner        = binfo[:owner]
      @summary      = binfo[:summary]
      @component    = binfo[:component]
      @pm_score     = binfo[:pm_score]
      @cust_cases   = binfo[:cust_cases]
    end

    def update(binfo)
      @last_seen    = binfo[:snapdate]
      @test_blocker = binfo[:test_blocker]
      @owner        = binfo[:owner]
      @summary      = binfo[:summary]
      @component    = binfo[:component]
      @pm_score     = binfo[:pm_score]
      @cust_cases   = binfo[:cust_cases]
    end

    def summary
      @summary[0..30].gsub(/\s\w+\s*$/, '...')
    end

    def age
      (@last_seen - @first_seen).to_i
    end
  end
end