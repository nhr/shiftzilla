# Shiftzilla
a.k.a "The tool that we made because Bugzilla lacks any meaingful aggreation reporting."

This is a specialized tool for aggregating Bugzilla records in a way that is useful for some development teams. In order to use it:

1. This utility depends on a python-based tool called [python-bugzilla](https://pypi.python.org/pypi/python-bugzilla).
    * Install it so that the `bugzilla` executable is in your $PATH
    * Configure it by running `bugzilla login`
2. Next grab this utility from RubyGems:
    * gem install shiftzilla
    * Run any command (like `shiftzilla summary`) to have the utility set up your local $HOME/.shiftzilla directory
3. Edit $HOME/.shiftzilla/shiftzilla_cfg.yml to reflect the right organizational info for your teams and groups, plus the saved reports in Bugzilla that you want to draw data from. The utlity expects three tables:
    * One for _all_ team bugs
    * One for bugs filtered by the release that you are tracking
    * One for bugs identified as test blockers by your QE team

With all of this done, you can start to run reports (or even set up cron jobs around them):
* `shiftzilla load` polls bugzilla and stores info in a local SQLite3 database
* `shiftzilla summary` gives you an overview report in your terminal
* `shiftzilla build` generates an overall and team-by-team reports that it will push to a web server as static web pages
