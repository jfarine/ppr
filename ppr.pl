#!/usr/bin/perl

# file name  : ppr_jf.pl - Personalized Peak Recognition
#              branched off 160419 18:10 from ppr_github/ppr.pl  !!! pirate copy !!!
# author     : initial J. Farine for Milandre Turb+Q data.
#              core developper C. Vuilleumier after 160415
#              Note: throughout the code, the comments [ NSF = "blah" ] stand for "Note For Self" 
#              and apply to JF
# purpose    : peak search
#              Gaps in the data properly detected and accounted for (to avoid false Delta-values)
#               - gaps are flagged when the time difference between successive points is larger 
#                 than the programmed probe sampling time, actually > parameter $thres_gap.
#                 $thres_gap is read from the 'rundata_<sampling point>.txt' file
#              The fine tuning parameters for the peak search are stored in the files
#                 'ppr_db_Q.txt' and 'ppr_db_T.txt' 
#              - see description below
# usage      : ppr.pl rfn [ploc]
#              where:
#              - rfn is the root file name used to build other filenames for this data, which are:
#                <rfn>.tod is the file with reformatted CaveLink data (last pt in file = latest in t)
#                <rfn>.tmp is a temp file that will be erased, or should have been :-)
#                <rfn>.csv is the data file suitable for "analysis" with Excel
#                <rfn>.dat is the data file suitable for analysis with PAW
#              - ploc is the probe location
#                [tmp for DB dev - not sure this is actually necessary ! see DB discussion below]
#              -> see FILE NAME CONVENTION below ! The syntax of 'rfn' must contain the 'sampling 
#                 point' and the data type or 'Observable' (Q or T)
# output fmt : Many ! see the code. Some outpit files get a legend printed on top. Some don't, in 
#              order to prevent crashes from the program that reads them (PAW, ROOT,..)
#              [NFS: the two lines below are likely obsolete]
#              Excel .csv: "%02d/%02d/%4d %02d:%02d, %+8.4f, %15.10f, %5.1f, %7.3f, %+9.5f, %+9.5f\n"
#              Data .dat and .spt: see code ! (both are read by ReadMoti.C as per 140227)
# description: - reads <time> <value> in input data file <rfn>.tod and searches for peaks
#              - the script now (160415) also allows input of the probe location ploc for future
#                use with DB (perhaps, see below)
#                Mechanism as per 160415:
#                - the script reads a second command line argument [ploc]; this is already obsolete:
#  !!>>          - FILE NAME CONVENTIONS !!!
#                  the input data file: <Observable>_<Sampling point>_<whatever>.tod where:
#                  - Observable is e.g. 'Q' or 'T' (variable name is $Obs)
#                  - Sampling Point is e.g. 'Amont', 'Gal80', 'Bure', 'Saivu' for T (or 'Saivu+Bame'
#                    for Q) (variable name is $SP)
#                  - whatever is free, but should not include '_' not '.'
#                  THE VALUES OF $Obs AND $SP ARE NOT HARD-CODED ANYWHERE !! By design ! Read on:
#                  -> example: the input file 'Q_Amont_2003.tod'
#                              implies $Obs="Q" and $SP="Amont"
#                              => script will look for the rundata file named 'rundata_Amont.text'
#                                 and for the DB file 'ppr_db_Q.txt' .. 
#                                 .. in which it will look for the 'Amont' data block
#                  -> other example: input file 'San_Gli_Er.tod' => 'rundata_Gli.txt' and block 
#                     named 'Gli' in DB file 'ppr_db_San.txt' ('Er' is treated as comment: ignored)
#              - the rate of change of level is produced in two units: m/h and cm/min [NFS: get rid
#                of redundance in ppr.pl]
#                IMPORTANT this rate is calculated **from the current to the next** pt,
#                          but because the data goes backward in time, the slope listed at one
#                          data point (time) is the slope ***to get to** this data point.
#                [NFS: the above was true in the initial script, where reformatting was done here.
#                      Not sure if it still applies, now that the reformatting was moved to the
#                      dedicated script cl_refmt.pl]
# definitions:
# - a _peak_ is a point in time where the quantity of interest (water level) reaches a local maximum
# - a _through_ (or valley) is " " " " " " " " .. local MIN [assoc'd var's are also called "_base"]
# - a _spate_ (or spate event, or flood, or high water event, crue en F) is the period of time
#   between two **throughs** (note: not between a peak and the next through)
# - ddoy means "digital day of the year" .. a bit of a misnomer: digital means a single scalar
#   instead of a list of integers: ddoy is the time (of anything) converted from
#   MM/DD/YY hh:mm:ss:cc to a real number. 
#   Conventions for this conversion vary, i.e. where 1 unit is either a year or a day;
#     the unit for ddoy is a day. 
#   So a std year starts at 0.00 (for Jan 1st 00:00) and ends at 365.00 (Dec 31st 24:00)
#     [ a leap year 366.00 ]
#   See subroutines DoYR and dysize [NFS: check what happens after 365 ..]
# - 160417: finally find some piece of mind: replace all cdyr and ddoy with good ol'unix epoch.
#     Yep, epoch.
#   Quite some coding to adapt though, reports included. Hope I did not break anything.
#   DECISION => Replacement of cdyr and ddoy by epoch implies using only units of 
#               qph = 'q'uantity 'p'er 'h'our
#               Gone are the mph, cm per min .. etc. Q and T a not in 'meter' anyway
#
# Versions:
# --- the following is left for background until 160415 --- may be obsolete ---
# 130421 - debugged txt version and downloaded data to play (49k requested)
#        - inverted DD and MM assignments, they were american! But checking again looked
#          right to do so as just above, I invert them so Excel has MM/DD/YYYY... TBC
# 140217 - Mavericks broke Perl .. comment out "require ctime.pl" and "use Switch"
# 140223 - added threshold detector for dh/dt, implemented code to detect 
#          (crue = rise, spate) - define spate if currt and last n_thres dh/dt are > $spate_thres_up
#          [ Note 160417: replaced lvl>qty, h>q do dh/dt > dhdt > dqdt ]
#        - a bit tricky given the data goes backwards (better: reordered file for off-line)
#        - also gives base / max levels for that spate
#        - saves spates in new file .spt - see code for format
#        - playing around with 'basic.dat' file to re-learn ROOT,
#          see macro hist1.cxx in moti/data/2014
# 140226 - added ttns_d time to next spate (days) (which was seen last since data is backwards)
#        - started serious ROOT macro - can now plot lvl, dh/dt and new_spate together
#          [ Note 160417: replaced lvl>qty, h>q ]
#          **from now on all new ROOT macros will be in ../macros**
#        - COMPLETELY REDEFINED TO PROCESS .tod FILES, i.e. CL's.txt processed by cl_refmt.pl
#        - ttns_d replaced by tsls_d - time since last spate (days)
# 140227 - added gap detector - prints message when time between entries is > 1/2h
#        - added data overlap detector - prints message when time interval is negative
#        - added SUM file for comments at the end
# 140302 - added calculation of avdhdt with n_avdhdht=6 ***MUST FINISH***
#        + added creation of a new data file for gaps in data
#        + tried replacing $above_thres condn from ">" to ">=" => mess
#          then reverted to ">" but used a slightly neg. $spate_thres_up value => mess
#          -> ok, this is nasty: all ref vals used are defined as a *minimum* but are def'd by
#             passing the "threshold condition for spate". A true minimum is only found
#             when slope is zero *and* going from - to + ..
#          => recoded this and test +- OK. "through" finding probby still buggy
#          -> Then tried to raise sensitivity to small spates 2011.900++
#             Dev' 3 methods for change of slope - none work!
#             See below under "try something different"
# 140304 - try adding to "algo3/4" requirement that 1st and 4th are 1
#        + require that last *two* points are not in spate
#        + require that there are at least $n_not_above_thres **before** current pt
#          (check if this is redundant with one before) -- well zero in 3/4 kills it!
#          -> replace by last_but2 (last *three* points not in spate)
#          + needed to add @dh_local_vals and set threshold to 3
#          => this seems to work OK - see TODOES
# 141021 - renamed .spt file .sptl (long) ..
#        + .. and *** implemented a shorter, 1 line-per-spate version called .spt ***
#          for DAN in ROOT. Problem: some spates have 0 or >1 peak (cannot be read as vectors)
#          => comment out pk and tr outputs for now, and just plot same range of data in ROOT
#             (initial intention was to only plot up to the next spate)
# 150906 - completed data from 20140223 to 21050907 12:00
#        - added legends to the top of files .spt and .sptl
#        - debugged bogus point 20110116 05:30 and removed it from the data set
# 160409 - minor changes to the doc - shared with Cécile
# 160414 - moved output of headers (legends) to top of files at user's request
#        + cleaned up indentation and typos in comments (a few)
# ------- created ppr.pl from cl2dat.pl ----------------------------------------------------
# 160415 - continued cleanup to collect all variables definitions where they belong
#          (customizable or not, loop inits or general inits, etc..), also added more doc
#        + implemented rundata mechanism, created template rundata file
#        + ran out of steam while working on db implem'ns
# 160416 - finished implementation of db file and parser;
#          tested ok (usage in script still to be implemented)
#          NOTE: IF EDITING THE LIST OF PARAMETERS, look for the following comment line
#                throughout the script:
#          ### edit the above if changing/adding/removing the db parameters
#          IMPORTANT:
#          ### The implementation is suboptimal in a number of ways:
#          ### 1) the test against rd/db variables is done for every point
#          ### 2) changing db pars while associated variables are being used is a Bad Idea.
#          ###    This could cause exceptions at execution time and/or make calculations
#          ###    meaningless, mostly because the depth of stacks could change.
#          ###    => a safe implementation would change DB values only between blocks of data
#          ###    => if changing DB valus within a block is unavoidable, proceed with care !
# 160417 - lame attempt to port to github and use XCode
#          - how to do it so that it is immediately "mirorred" locally ?
#            I had to "dnld to PC and open in GH-DT", which created a new copy in repo subdir?!?
#            How do I get GitHub to just use the original file ?!?
#          - XCode newproject OK, import file OK, perl syntaz highlighting fine but..
#            - creating a new Scheme to run perl on script with Cmd-R all went ok..
#            - .. but hitting Cmd-R opens a thread in an editor-like window.. 0 _dyld_start ?!?
#              ==> ok could fix that: tick off "Debug executable" in "Edit (current) Scheme.."
#                  output window now shows same as when run from the shell
#                  [ and Scheme is configured to run in ~BSS/160414/160415tests, with two arguments,
#                    **in that order**:
#                  ppr_github/ppr.pl
#                  Q_Amont_2003test.tod ]
#            - must also figure out how to create lib with my symbols in Perl. Current syntax
#              higlighting has col defines for Project/local variables..  but they are not applied.
#              ..few hours later: doesn't seem to have interested anybody to implement
#        + replaced all cdyr and ddoy with good ol'unix epoch - finally a proper time ref. 
#          -> preserved datetime strings in script and rundata/db for human consumption
#          -> caused renaming of many variables; rates of change per minute were dropped
#          -> revisited entire code to ensure integrity of data calculations and usage
#          -> including necessary changes to output files (checked all)
#          Note: some points are not cristal-clear: they are marked with ### MUST CHECK ###
#        + replaced function and meaning of $n_spate_thres_up with
#          $n_recent_to_consider and $n_slope_up_above_thres
#          -> included one more parameter in db file, and updated all db related code
#        + removed all references to "level, height, meters, centimeters, .." (except in a
#          few comments for reference)
#          -> all of those are now called 'quantity/ies': lvl->qty; h->q; m(eters)->q
#          -> caused renaming of many variables; cm were dropped, output files accordingly simpler
#        -> all these mods let to a change of unit of the DB parameter spates_thres_up :
#           from cm/min to qty/hour or qph
#        + some logics was checked, a few bugs were fixed or clarified as not being bugs (they
#          are marked individually)
#        + some possible redundancy: are spate_thres_up and thres_up doing the same thing ?
#        + updated the documentation in the script and in template rundata and db files (more
#          clean up work needed, best after logics is debugged)
#        => wait for Cecile to get a GitHub account and will make her Principal Collaborator
#        => still not done: the full intricacies of the PR logics. This required all the above
#           to be polished first.
# 140619-24: version pirate ! fait tous les changements discutés dans _notes, super bien nettoyé
#            les formats output, rajouté des prints avec $verbose_stack,$verbose_peaks associés;
#            tout reformatté code+commentaires pour qu'ils tiennent dans < 104 colonnes => imprimé
#            en couleurs (36 pages) .. créé nouveau fichier _notes_160423 avec TdM et suivi de 
#            variables, tout ça pour aider Cécile à y voir plus clair
#
# 
# TODOes:
# 130806 - document which format is required: this first removes all "<br>"'s, so html save
#        - auto-recognize data format OR (preferred) impose a single way of downloading the data
#        - autodownload
#        - autoappend to SUM(mary) files (per year, all cumulated, per data type,..)
# 140226 - check calculations of start-to-peak delta_days for spates
#        + reorder all data back in time , save this to file, use reordered file for all calcs
#        + split script int two:
#          a) - generate time-ordered CL data
#             - concatenate all years (read: add to existing summary file)
#          b) - then run calculations, searches for spates etc.. on this one
#          Note: *two* dates should always be involved: 1-data retrieval; 2-dan
#        + spate detector: slope dh/dt> is not strictly correct. Correct criterium is:
#          dh/dt > slope of <intake-free discharge for this level>
#          [ Note 160417: replaced lvl>qty, h>q do dh/dt > dhdt > dqdt ]
#          (Q: is that slope always the same at the same levels ?? - need data)
# 140302 - see notes above under same dates
#        - check new peak calculations, esp. throughs - dates to <peak> can be odd
#        - check 3/4 algo, improve, implement to peaks/throughs too
# 140304 - Trigger:
#          - replace last_but1|2 with test on n_not_in_spate >= n_not_in_spate_req & check still OK
#          + still missing b7 (requires now arrays of size 5, not 4.. re-include dh_local_vals then)
#            [ Note 160417: replaced lvl>qty, h>q do dh/dt > dhdt > dqdt ]
#          + still triggering on fake b10b
#          + fluke ns#1 2011.0428652968
#          + flukes from fluctuations during single, nice broad event
#          + look at all data from start and  polish algo
#          + revisit bump-finding ! e.g. 0.11 -> check out 
#            http://search.cpan.org/~randerson/Statistics-LineFit-0.07/lib/Statistics/LineFit.pm
#        + Peak/trough calculations
#          - check
#          - sp. after 2011.908 - next Pk is from before!!
# 150907 - for DAN really:
#          - determine if the first and second 1/2h IVL can predict the overall magnitude of 
#            the spate (see 20110901 16:30)
# 160414 - debug needed: look for #BUG<n>#, n=1,2,3,..
#        + cleanup doc: look for [NFS .. ]
# ------- created ppr.pl from cl2dat.pl ----------------------------------------------------
# 160415 - debugging needed as per above
#        + also debug argument passing to subs (now two mechanisms !!)
#        + get rid of anything talking about level, centi/meters etc.. this should be generic
#          value/unit ( either Turb or Q)
#        + similarly, make clear that Sampling Time ST is always specified in MINUTES
#        + [ NSF: refresh my memory on how thresholds & criteria work. For one: what does
#            $gap_max wrt $thres_gap ? ]
#        + DATABASE PRELIMINARY IDEAS -- no decisions made yet !!! 
#          need to implement a database mechanism to do 1) and 2) below
#          1) load peak search parameters from external data files,
#             named e.g. ppr_db_T.txt and ppr_db_Q.txt (turb/discharge "probes" are different),
#             with possibly a Makefile syntax like:
#               Sonde Turbidity No. 1 - Amont
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	...
#               Sonde Turbidity No. 2 - Galerie 80
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	…
#               Sonde Turbidity No. 3 - Affluent de Bure
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	...
#               Sonde Turbidity No. 4 - Saivu
#                 start_time	end_time		P1	P2	P3	...
#                 start_time	end_time		P1	P2	P3	...
#        + 2) implement similar idea for describing the input data to the script, with ext'l files
#             named e.g. rundata_<location>.txt, with possibly a Makefile syntax like:
#               Sonde Turbidity No. 1 - Amont
#                 start_time	end_time		thres_gap	...
#                 start_time	end_time		thres_gap	...
#          rationale:
#             i)  the *format* of the data is set by how the probe is programmed,
#                 and when the probe is on or off; the point here is to tell the program
#                 what data and what absence of data are legitimate
#             ii) the *quality* of the data (which impacts peak recognition) is set by
#                 environmental factors (noise, sediment plate-out on probe,..)
#             => the two can vary independently with time; they are different things, they
#                belong to separate files
#        + IMPORTANT! must decide asap that <Sonde [..whatever..] No. N - Location> is actually
#          a **location in the karst** and not a particular probe, i.e. "Schneggomètre No. 314"
#          A this stage, it only matters to keep track of wehre in the karst the data applies;
#          and managing the details of how it has been acquired must be managed elsewhere.
#        + Implementation ideas: (reminder: rfn = root file name)
#          - script is invoked from master script with two arguments: rfn and ploc
#            - rfn points to the input data file and creates all output files with same rfn
#            - rfn contains a "waveform" <time> <value>; gaps are allowed (periods without data),
#              else data is assumed at regular sampling time intervals ST
#            - the script looks for peaks (and other structural parameters) in the data
#            - to do that effectively, the script needs to know of:
#              1) parameters to optimize the peak search as data quality may vary within
#                 the waverform (achieved with DB files ppr_db_[T|Q].txt)
#              and also of:
#              2) the data fmt, like the current ST (achieved with DB files rundata_<location>.txt)
#            - for this the script needs to know a) if it is looking at Turb or Q and
#              b) the probe location
#            - it will then figure out which pars to use as time goes by directly from the DB
#              [NFS: careful with boundaries of time ranges !! best if they fall in periods with
#               probe off ? ]
#            => it is not obvious to me that ploc needs to be specified on the command line ! 
#               a cleaner mechanism: craft rfn to include ploc, i.e. $rfn="Q_<ploc>_other.dat"
#               i.e. a disciplined, fixed format rfn will allow the script to find its pointers
#               to the DB
#               (e.g. in the example above from Cécile, rfn already contains either T or Q !)
#        -> running out of steam at the end of 160415 .. rundata implemented, but not db yet
# 160416 - eval if the ampl of the <observable> (level) should be taken into account too in the
#          spate detector. It was not the case in Môtiers, but for probes with a long ST,
#          like >= 1h, it might be relevant and increase the sensitivity to small spates.
#        => TBD later if of interest and worth the time - by core developper :-)
# 160417 - are spate_thres_up and thres_up doing the same thing ?
#        => can now debug the entire logics in all its glory .. 
#        + documentation: more clean up work needed, but best done after logics is debugged
#        + then can trim down a lot of comments, and move on with a leaner file
#          (1804 lines as per tonight)
#
# Careful, this is the end of the list of TODOes, not Versions !!
# add new TODOes above 'Careful', and new Versions above 'TODOes' :-)

### start by formally requiring all external perl packages needed by this script
### (for Python users this is the "import" block of the script)
# require "ctime.pl";
use     Sys::Hostname;
# not sure why I commented following line out ..
# use 	Switch;
# but 'use  feature switch' is available since perl 5.10.1 according to 
#           http://perldoc.perl.org/perlsyn.html#Switch-Statements
use		  Math::Trig;
# these added 160415 JF to pass file handles to a subroutine.. 
# .. well, the example I found 'used' these two, so I just stupidly copy them here,
#    not sure they are needed. Later: comment them out
# Getting errors, I commented them out and my copy-pasted snippet just works FINE.
# use     strict;       # should read http://perldoc.perl.org/strict.html
# use     warnings;     # should read http://perldoc.perl.org/warnings.html
use     DateTime;     # added 160417 for robust datetime handling

### CUSTOMIZABLE PARAMETERS +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
#
# Note: in an upcoming update, pars in categories custo2+3 will be read from an external
#       text file, the "database". Definitions will always remain here, just that they
#       might get overwritten

# custo 1 - this is to alter how the program behaves in general
$verbose                   =      0;   # set to 1 for debugging, 0 = silent
$verbose_stack             =      0;   # same, only for prints related to debugging of stacks
$verbose_peaks             =      1;   # same, only for prints related to peak/trough searches
 
# custo 2 - this is to inform the program about the data it is being given
$path_rundata              =    ".";   # tell script where to find DB rundata_<location>.txt files
#                                      # script will then look for sample location $SP in $rfn to
#                                      # construct full rundata file name
# gap detector - will look for gaps in data by flagging intervals between points > $thres_gap 
# (this is about finding out when data is missing)
$thres_gap                 =     31;   # time in minutes

# custo 3 - this is to fine tune the peak search
$path_db                   =    ".";   # tell script where to find DB ppr_db_[Q|T].txt files
## number of intervals to include in avdhdt  (#BUG2#? this is used nowhere in the code ?!?)
$n_avdhdt                  =      6;
## requirements to define spate (up) or peak (down) conditions
# Note the different uses  to avoid false positive triggers !!
# the following obsoleted on 160417 and replaced by the next two
# $n_spate_thres_up          =      4;   # number of consec. data points that must be above thresh.
$n_recent_to_consider      =      4;   # nb of consec. data pts that must be looked at for
                                       #   being above threshold or not
$n_slope_up_above_thres    =      3;   # number of data points in the $n_recent_to_consider
                                       #   most recent that must be above threshold
$spate_thres_up            =      0;   # threshold value [qty/hour] (must experiment with data)
                                       ### UNIT WAS cm/min before
$n_not_in_spate_req        =      3;   # request that these many pts are "not in spate" prior to
                                       # allowing a new spate (#BUG3#? - formerly said not not in
                                       # spate) #$ 160418 JF unused !!
$dq_local_min              =      3;   # min raise requested [ Note: when q was h, this was
                                       # "in (in mm) between [0] and [3]" - TBD now ]
## the following is for peak/through detection
# peak/through detector have a slightly different logics
# careful with confusion up/dn here: read <whatever> "for ending going _up/_dn after passing the pt"
$n_thres_up                =      4;   # nb consec. data pts that must slope *dn* b4 the one going up
$thres_up                  =      0;   # threshold value [qty/hour] (must experiment with data)
$n_thres_dn                =      4;   # nb consec. data pts that must slope *up* b4 the one going dn
$thres_dn                  =      0;   # threshold value [qty/hour] (must experiment with data)
### edit the above if changing/adding/removing the db parameters
# IF UDATING NUMBER OF DB PARAMETERS THE FOLLOWING MUST BE UPDATED TOO 
$n_db_params               =      9;   # number of parameters in database
### edit the above if changing/adding/removing the db parameters
### END OF CUSTOMIZABLE PARAMETERS +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-

# consistency checks on the above
if ($thres_up < $thres_dn){
	  die("Error: slopes thres_up=%f < thres_dn=%f (they can be equal)\ndie\n",$thres_up < $thres_dn);
}

# $syscmd = "cat motidata_20110729_0700.txt | sed -e 's/<br>/\
# /g' > " . $fnam;
# print "about to execute syscmd=$syscmd\n";
# system($syscmd);
# curl ${url}${pict} > ${fnam}
# curl ${url} > ${fnam}

######### IGNORE ABOVE FOR FINAL SCRIPT #################### (#BUG4# what was this ?)
# the following defines are essential for date calculations
@mdays   = ( '31', '28', '31', '30', '31', '30', 
	      '31', '31', '30', '31', '30', '31' ) ;
@cmonths = ( 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
	      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' ) ;


#### PROCESS COMMAND LINE INPUT ###
## for debugging ..
# print "ARGV 0 = $ARGV[0]\n";
# exit;

## Get positional arguments from command line
# get root file name
$rfn=$ARGV[0];
# get probe location - must define format - probably not needed: see DB discussion
$ploc=$ARGV[1];
# get <TBD>
# $=$ARGV[2];
## debug
print "ARGV 0 = $ARGV[0], ARGV 1 = $ARGV[1], ARGV 2 = $ARGV[2]\n" if ($verbose);
print "rfn = $rfn; ploc = $ploc\n" if ($verbose);

#### LOAD AND CHECK DB AND RUNDATA
# Note on variables name convention.
# To avoid confusion I decided the call the variables associated with parameter 'par':
# - 'par_<blah>' : variables that are read form the <blah> file (blah= 'rundata' or 'db')
#                  - these are scalars (one value)
# - '<blah>_par' : variables used in memory in this script to be checked against as script
#                  progresses - these are vectors (>=1 value/s)
### extract from rfn the fields necessary to build the appropriate rundata/DB file names
# $rfn =~ /^(\w)_([^\W_]+)_[^\.]+\.tod/;      # doesn't work
# $rfn =~ /^([^\W_])_([^\W_]+)_[^\.]+\.tod/;  # doesn't work
$rfn =~ /^([^\W_])_([^\W_]+)_/ 
  || die "\nERROR: syntax incorrect in filename $rfn:\n expecting X_aaaaa_text.tod\ndie\n\n";
$Obs=$1;    # Observable : e.g. 'Q' or 'T'
            # (but this is hard-coded nowhere, so it could be nay character !)
$SP=$2;     # Samplg Point: e.g. 'Amont', 'Gal80', 'Bure', 'Saivu' for T (or 'Saivu+Bame' for Q)
## debug
print "Obs = $Obs; SP = $SP\n" if ($verbose);
### construct file names
$rundata_fn = sprintf("%s/rundata_%s.txt",$path_rundata,$SP);
$db_fn      = sprintf("%s/ppr_db_%s.txt", $path_db,$Obs);
print "rundata_fn = $rundata_fn\n" if ($verbose);

### rundata: open, load and close rundata file
open(RDF,"$rundata_fn")    || die "Can't open  input file: $rundata_fn, $!\n"; 
print "\nsucessfully opened rundata file $rundata_fn\n" if ($verbose);
read_rundata();
close(RDF); 
print "rundata_start_epoch  = @rundata_start_epoch\n" if ($verbose);
print "rundata_end_epoch    = @rundata_end_epoch\n" if ($verbose);
print "rundata_start_t      = @rundata_start_t\n" if ($verbose);        
print "rundata_end_t        = @rundata_end_t\n" if ($verbose);        
print "rundata_thres_gap    = @rundata_thres_gap\n" if ($verbose);        
### check consistency of rundata time ranges (any variable can be used to obtain highest index)
### comparison using epoch, reporting using (human) _t
for ($i=0;$i<=$#rundata_start_t;$i++){
    # check 1: start(i) must be < end(i)
    if($rundata_start_epoch[$i] >= $rundata_end_epoch[$i]){
        $msg = sprintf(
               "ERROR in rundata file %s: start time %s >= end time %s (epochs)\n",
               $rundata_fn,$rundata_start_t[$i],$rundata_end_t[$i]);
        die($msg);
    }
    # check 2: end(i) must be < start(i+1)
    if($i < $#rundata_start_t){
        if($rundata_end_epoch[$i] >= $rundata_start_epoch[$i+1]){
            $msg = sprintf(
                   "ERROR in rundata file %s: end time %s >= next start time %s (epochs)\n",
                   $rundata_fn,$rundata_end_t[$i],$rundata_start_t[$i+1]);
            die($msg);
        }
    }
}
print "No time inconsistencies found in rundata file $rundata_fn,\n\n" if($verbose);
print "  of interest to sampling point $SP\n\n" if($verbose);


### database: open, load and close DB file
open(DBF,"$db_fn")    || die "Can't open  input file: $db_fn, $!\n"; 
print "\nsucessfully opened db file $db_fn\n" if ($verbose);
read_db();
close(DBF); 
print "db_start_epoch               = @db_start_epoch\n" if ($verbose);
print "db_end_epoch                 = @db_end_epoch\n" if ($verbose);
print "db_start_t                   = @db_start_t\n" if ($verbose);
print "db_end_t                     = @db_end_t\n" if ($verbose);
## RETIRED 160417 ## print "db_n_spate_thres_up     = @db_n_spate_thres_up\n" if ($verbose);
print "db_n_recent_to_consider      = @db_n_recent_to_consider\n" if ($verbose);
print "db_n_slope_up_above_thres    = @db_n_slope_up_above_thres\n" if ($verbose);
print "db_spate_thres_up            = @db_spate_thres_up\n" if ($verbose);
print "db_n_not_in_spate_req        = @db_n_not_in_spate_req\n" if ($verbose);
print "db_dq_local_min              = @db_dq_local_min\n" if ($verbose);
print "db_n_thres_up                = @db_n_thres_up\n" if ($verbose);
print "db_thres_up                  = @db_thres_up\n" if ($verbose);
print "db_n_thres_dn                = @db_n_thres_dn\n" if ($verbose);
print "db_thres_dn                  = @db_thres_dn\n" if ($verbose);
### edit the above if changing/adding/removing the db parameters

### check consistency of db time ranges (any variable can be used to obtain highest index)
### comparison using epoch, reporting using (human) _t
for ($i=0;$i<=$#db_start_t;$i++){
    # check 1: start(i) must be < end(i)
    if($db_start_epoch[$i] >= $db_end_epoch[$i]){
        $msg = sprintf(
               "ERROR in db file %s: start time %s >= end time %s (comparing epochs)\n",
               $db_fn,$db_start_t[$i],$db_end_t[$i]);
        die($msg);
    }
    # check 2: end(i) must be < start(i+1)
    if($i < $#db_start_t){
        if($db_end_epoch[$i] >= $db_start_epoch[$i+1]){
            $msg = sprintf(
                   "ERROR in db file %s: end time %s >= next start time %s (comparing epochs)\n",
                   $db_fn,$db_end_t[$i],$db_start_t[$i+1]);
            die($msg);
        }
    }
}
print "No time inconsistencies found in DB file $db_fn,\n" if($verbose);
print "  of interest to sampling point $SP and observable $Obs\n\n" if($verbose);

# a convenient stop when debugging rundata + DB mods:
# exit;


#### CREATE I/O FILE NAMES
# this was for debugging
# $fnam="motidata_20110729_0700.txt";
# $tnam="motidata_20110729_0700.tmp";
# $dnam="motidata_20110729_0700.dat";
$tnam   = $rfn . ".tod";  # IDF
$enam   = $rfn . ".csv";  # ODF
$dnam   = $rfn . ".dat";  # ODDF
$snam   = $rfn . ".spt";  # ODSF  - spate starts and levels - short version for root
$slnam  = $rfn . ".sptl"; # ODSLF - spate starts and levels - long version for one human
$gnam   = $rfn . ".gap";  # ODGF  - gaps in data
$sumnam = $rfn . ".sum";  # OSF   - summary file
# $testnam = "basic.dat"; # ODTF


#### PREPARE OUTPUT FILES: open and write headers if applicable

# ## first pass to get rid of <br>'s 
# ## (this is historic and now in cl_refmt.pl, but I leave it there as
# ##  it's kind of cute how EOLs are translated - and it could be handy too)
# open(IDF,"$fnam") || die "Can't open input file: $fnam, $!\n";  
# open(ODF,">$tnam") || die "Can't open output file: $tnam, $!\n";  
# # ignore header (i.e. read the two lines and do nothing about them)
# <IDF>;
# <IDF>;
# # bulk
# while(<IDF>) {
#     $_ =~ s/\<br\>/\n/g;
#     printf (ODF "%s",$_);
# }
# close(IDF);
# close(ODF);

open(IDF,  "$tnam")    || die "Can't open  input file: $tnam, $!\n";  
open(ODF,  ">$enam")   || die "Can't open output file: $enam, $!\n";  
open(ODDF, ">$dnam")   || die "Can't open output file: $dnam, $!\n";  
open(ODSF, ">$snam")   || die "Can't open output file: $snam, $!\n";  
open(ODSLF,">$slnam")  || die "Can't open output file: $slnam, $!\n";  
open(ODGF, ">$gnam")   || die "Can't open output file: $gnam, $!\n";  
open(OSF,  ">$sumnam") || die "Can't open output file: $sumnam, $!\n";  
# open(ODTF,">$testnam") || die "Can't open output file: $testnam, $!\n";  

# print out some headers
# REF FOR ODDF
# 1=up_met  2=is_max    3=dn_met  4=is_min    5=above_thres  6=in_spate    7=n_not_in_spate  8=new_spate
# --- End of Legend ---
# YYYY MM DD hh mm  ____qty___  ___epoch__  _dqdt_qph  ___DSL___  t x  t n  ____dq____  _dq_local_  s e     e e
# 2014 12 08 08 00     -7.5515  1418025600   +0.00000  +0.00E+00  0 9  0 9     +0.0000     +0.0000  0 0     0 0
$padding1 = 
 "                                                                ";
$padding2 =                                                              "                          ";
# modified by CV 160418 so that each column is described by exactly one keyword
# printf (ODDF "Legend:\n");
printf (ODDF "YYYY MM DD hh mm  ____qty___  ___epoch__  ");
# pirate !# printf (ODDF "YYYY MM DD hh mm qty epoch ");
printf (ODDF "_dqdt_qph  ");   # dqdt_cmpm");
# printf (ODDF "  _DeltaSL_  From here on, a galore of 1/0 flags, in this order:\n");
#printf (ODDF "  From here on, a galore of 1/0 flags, in this order:\n");
#printf (ODDF "above_thres new_spate  "); # this should not be here (CV 160418)
#printf (ODDF "9.2E is DSL (Delta of avge slopes as (ASL1-ASL2)/ASL1)\n");
printf (ODDF "___DSL___  ");
# printf (ODDF "up_met is_max  dn_met is_min  ");
# printf (ODDF "1 2  3 4  ");
# printf (ODDF "u i  d i  ");
  printf (ODDF "_ _  _ _  ");
#printf (ODDF "+7.1f: dq_local ");
printf (ODDF "____dq____  _dq_local_  ");
# printf (ODDF "above_thres in_spate ");
# pirate !# in_spate_last in_spate_last_but1 in_spate_last_but2 ");
# printf (ODDF "n_not_in_spate new_spate\n--- End of Legend ---\n");
# printf (ODDF "5 6  ___7 8\n"); 
# printf (ODDF "a i  n_!i n\n"); 
  printf (ODDF "a _  n_no _\n"); 
# printf (ODDF "1=up_met  2=is_max    3=dn_met  4=is_min\
#  5=above_thres  6=in_spate    7=n_not_in_spate  8=new_spate\n");
printf (ODDF "%s        %sb       t  \n",$padding1,$padding2);
printf (ODDF "%s        %so       | n\n",$padding1,$padding2);
printf (ODDF "%s        %sv i     i e\n",$padding1,$padding2);
printf (ODDF "%s        %se n     n w\n",$padding1,$padding2);
printf (ODDF "%su i  d i%s| |     | |\n",$padding1,$padding2);
printf (ODDF "%sp s  n s%st s     s s\n",$padding1,$padding2);
printf (ODDF "%s| |  | |%sh p     p p\n",$padding1,$padding2);
printf (ODDF "%sm m  m m%sr a     a a\n",$padding1,$padding2);
printf (ODDF "%se a  e i%se t     t t\n",$padding1,$padding2);
printf (ODDF "YYYY MM DD hh mm  ____qty___  ___epoch__  ");
printf (ODDF "_dqdt_qph  ");
printf (ODDF "___DSL___  ");
printf (ODDF "t x  t n  ");
printf (ODDF "____dq____  _dq_local_  ");
printf (ODDF "s e     e e\n");
# printf (ODDF "--- End of Legend ---\n");
# printf (ODDF "n_not_in_spate new_spate\n");

printf (ODSF "Legend:\nnspat _tsls_d  ___epoch__ ___qty__  \n--- End of Legend ---\n");

printf (ODSLF "Legend:\nns\# nspat (pt _____ID): YYYYMMDD hh:mm  _tsls_d  ___epoch__ _____qty__  ");
printf (ODSLF "pk: YYYYMMDD hh:mm ___qtymax_  ____dqty__  __Ddays+");
printf (ODSLF "\n                                                                        ");
printf (ODSLF "tr: YYYYMMDD hh:mm ___qtymin_  ____dqty__  __Ddays-\n");
printf (ODSLF "--- End of Legend ---\n");

printf (ODGF "threshold for detection of gaps = %d min\n",$thres_gap);


#### PROCESS INPUT DATA FILE

### GLOBAL INITS (ok, a bit of a misnomer)
## Do **not** change those unless you know what you are doing
# scan for absolute extrema - start by setting impossible values
$qty_abs_min        = +60;
$qty_abs_max        = -20;
$qty_abs_min_epoch  =   0.;
$qty_abs_max_epoch  =   0.;
$qty_abs_min_YMDhm  =   0;
$qty_abs_max_YMDhm  =   0;
$dqdt_abs_min       = +20;
$dqdt_abs_max       = -20 ;
$dqdt_abs_min_epoch =   0.;
$dqdt_abs_max_epoch =   0.;
$dqdt_abs_min_YMDhm =   0;
$dqdt_abs_max_YMDhm =   0;
$dqdt_abs_min_qty   = +60.;
$dqdt_abs_max_qty   = -20.;


#### INITs for peak search -- this section has no parameters to modify. 
## Do **not** change those unless you know what you are doing
$epoch_last=0;
$qty_last=0;
$ndata=0;
$ngap=0;
$gap_max=$thres_gap;
$novlap=0;
$nspate=0;
$in_spate=0;
$n_not_in_spate=0;
$in_spate_last=0;
$in_spate_last_but1=0;
$in_spate_last_but2=0;
$dq_max=0;
$new_spate=0;
$last_spate_epoch=0;
$dqdt_qph_last=0;
$YY_last=0;
$is_max=9;
$is_min=9;
$theta=-9.99;

# bulk - a standard input line follows for reference (**after** substitution of '.' with '/')
# 7/29/2011 06:00, -1.8464

# track stacks
printf (STDOUT "Tracking stacks:\n") if($verbose_stack);
printf (STDOUT "NestingLvl ndata  idx  idx  idx\n") if($verbose_stack);
printf (STDOUT "           point  evt  n>1  rct\n") if($verbose_stack);
printf (STDOUT "-------------------------------\n") if($verbose_stack);

# loop over input data
while(<IDF>) {

    # # first substitute delimiter that Excel doesn't like
    # $_ =~ s/(\d+)\.(\d+)\.(\d{4})/$2\/$1\/$3/g;
    # # printf (ODF "%s",$_);
    chop();

    # next, extract fields
    # print ">$_<\n";
    $_ =~ /^(\d{4})\/(\d{2})\/(\d{2})\s*(\d{2}):(\d{2}),\s*((\+|-)\d+\.\d+)/;
    $YY=$1;
    $MM=$2;
    $DD=$3;
    $hh=$4;
    $mm=$5;
    $qty=$6;
    # print "$YY$MM$DD $hh:$mm qty=$qty qty_last=$qty_last\n";
    
    ### 160417 moved from Gnarfer DoYR, dysize etc.. to epoch
    # # cdyr calculations                      # #BUG6# looms here  ***done*** obsoleted 160417
    # $cdoy=&DoYR($DD,$MM,$YY);                       # current day of the year
    # $ddoy=$cdoy + (($mm/60.)+$hh)/24.;              # real time in units of day of the year
	  # $dy=&dysize($YY);                               # days in current year
	  # $dy_last=&dysize($YY_last);                     # days in "the year of the last (prev) data pnt"
	  # $cdyr=$YY+( (($mm/60.)+$hh)/24. + $cdoy )/$dy;  # Digital (real) year coordinate <==
	                                                    # this is #BUG6#  ***done*** obsoleted 160417
    # # print "cdoy=$cdoy, dy=$dy, cdyr=$cdyr, cdyr_last=$cdyr_last\n";

    # replaced with epoch: 
    $dt = DateTime->new(year => $YY, month => $MM, day => $DD, hour => $hh, minute => $mm);
    $epoch = $dt->epoch();                            ### ***of current point ***
    # have some merci for humans:
    $datetime = sprintf ("%4d%02d%02d %02d%02d",$YY,$MM,$DD,$hh,$mm);
    print "\n--- Here at $datetime ---\n" if ($verbose);

    $ndata++;
    
    ### 160417 I don't think this is necessary any more, using epoch
    if($ndata == 1){
    	  $YY0=$YY;
    }

	  # this is kind of a cheap "pause", asking the program to wait for input
	  # $blah=<STDIN>; 
	
  	# update abs extrema if applicable
	  if($qty > $qty_abs_max) {
        $qty_abs_max = $qty;
        $qty_abs_max_epoch = $epoch;		
        $qty_abs_max_YMDhm = sprintf("%4d%02d%02d %02d%02d",$YY,$MM,$DD,$hh,$mm);		
	  }
        if($qty < $qty_abs_min) {
        $qty_abs_min = $qty;
        $qty_abs_min_epoch = $epoch;
        $qty_abs_min_YMDhm = sprintf("%4d%02d%02d %02d%02d",$YY,$MM,$DD,$hh,$mm);		
	  }
	
	  # running min/max qtys
    if($ndata == 1) {
		    &setmax();
		    &setmin();
    } else {
        if($qty > $qty_max) {
            # printf (STDOUT "at ndata=%5d, qty=%10.3f > qty_max=%10.3f, invoke setmax()\n",
            #         $ndata,$qty,$qty_max) if($verbose_peaks);
            if($verbose_peaks){
                $last_setmax_call_ndata=$ndata;
                $last_setmax_call_qty=$qty;
            }
			      &setmax();
        }
        if($qty < $qty_min) {
            # printf (STDOUT "at ndata=%5d, qty=%10.3f < qty_max=%10.3f, invoke setmin()\n",
            #         $ndata,$qty,$qty_max) if($verbose_peaks);
            if($verbose_peaks){
                $last_setmin_call_ndata=$ndata;
                $last_setmin_call_qty=$qty;
            }
			      &setmin();
        }
    }

	  # yet another local variable, will store 5 (highest index 4)
	  push(@dq_local_vals, $qty);  
	  push(@last_datetime_vals, $datetime);  
	  
	  # try and follow stack sizes by printing highest index
	  printf (STDOUT "event loop %5d   %2d  %2d  %2d\n",
	          $ndata,$#dq_local_vals,$#last_thres_vals,$#last_in_spate_vals)
	              if($verbose_stack);
	  	  
	  ### Obtain parameters from rundata and DB files +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
	  ### --- use point of rundata+DB---
	  ### The implementation is suboptimal in a number of ways:
	  ### 1) the test against rd/db variables is done for every point
	  ### 2) changing db parameters while associated variables are being used in a Bad Idea.
    ###    This could cause exceptions at execution time and/or make calculations
    ###    meaningless, mostly because the depth of stacks could change.
	  ###    => a safe implementation would change DB values only between blocks of data
	  ###    => if changing DB valus within a block is unavoidable, proceed with care !

	  ## 1) rundata
    # # for testing during commissionning: 
	  # print "\n epoch=$epoch;  thres_gap b4 = $thres_gap, ";
	  # check 1: $epoch is within time extrema in file
	  if ($epoch < $rundata_start_epoch[0] || $epoch > $rundata_end_epoch[$#rundata_end_t]){
        $msg = sprintf (
              "ERROR current point's time %s (epoch %s) out of scope of file %s:\n");
           $datetime,$epoch,$rundata_fn);
        die($msg);
	  }
	  $found=0;
	  for ($i=0;$i<=$#rundata_start_epoch;$i++){
        # check 2: is $epoch in current interval ?
        if($rundata_start_epoch[$i] <= $epoch && $epoch <= $rundata_end_epoch[$i]){
            $found=1;
            $thres_gap = $rundata_thres_gap[$i];
            # # for testing during commissionning: 
            print "ndata=$ndata [found match in rd block $i ] \n" if($verbose);
            # goto AFTER-RD-LOOP;
            ## this is a hack - to get out of the loop
            ## $i=$#rundata_start_t;
            ## ahem - there is a builtin for that:
            last;
        }
    }
    # AFTER-RD-LOOP:
    # this generates and error, and 'Learning Perl' tells me to never use 'goto' ..
    $msg = sprintf (
           "ERROR current point's time %s (epoch %s) fell through the cracks of file %s:\n",
           $datetime,$epoch,$rundata_fn);
    die($msg) if ($found == 0);
    # # for testing during commissionning: 
	  # print " aft = $thres_gap\n";
    # $blah=<STDIN>;
    
	  ## 2) DB next
    # # for testing during commissionning: 
	  # print "\n epoch=$epoch;  VARTBD b4 = $VARTBD, ";
	  # check 1: $epoch is within time extrema in file
	  if ($epoch < $db_start_epoch[0] || $epoch > $db_end_epoch[$#db_end_t]){
        $msg = sprintf (
              "ERROR current point's time %s (epoch %s) out of scope of file %s:\n");
           $datetime,$epoch,$db_fn);
        die($msg);
	  }
	  $found=0;
	  for ($i=0;$i<=$#db_start_epoch;$i++){
        # check 2: is $epoch in current interval ?
        if($db_start_epoch[$i] <= $epoch && $epoch <= $db_end_epoch[$i]){
            $found=1;
            # $n_spate_thres_up         = $db_n_spate_thres_up[$i];
            $n_recent_to_consider     = $db_n_recent_to_consider[$i];
            $n_slope_up_above_thres   = $db_n_slope_up_above_thres[$i];
            $spate_thres_up           = $db_spate_thres_up[$i];
            $n_not_in_spate_req       = $db_n_not_in_spate_req[$i];
            $dq_local_min             = $db_dq_local_min[$i];
            $n_thres_up               = $db_n_thres_up[$i];
            $thres_up                 = $db_thres_up[$i];
            $n_thres_dn               = $db_n_thres_dn[$i];
            $thres_dn                 = $db_thres_dn[$i];
            # # for testing during commissionning: 
            print "ndata=$ndata [found match in db block $i ] \n" if ($verbose);
            # goto AFTER-RD-LOOP;
            ## this is a hack - to get out of the loop
            ## $i=$#db_start_t;
            ## ahem - there is a builtin for that:
            last;
        }
    }
    # AFTER-RD-LOOP:  # this generates and error, and 'Learning Perl' tells me to never use 'goto' ..
    $msg = sprintf (
           "ERROR current point's time %s (epoch %s) fell through the cracks of file %s:\n",
           $datetime,$epoch,$db_fn);
    die($msg) if ($found == 0);
    # # for testing during commissionning: 
	  # print " aft = $VARTBD\n";
    # $blah=<STDIN>;
    ### edit the above if changing/adding/removing the db parameters


    # Rate of change calculations
    #     If not first point read, should write calculations from "previous"
    # point (which is more recent), before writing data from CaveLink from current
    # IMPORTANT: read note in Description in top: the data goes backwards in time
    # and the consequence is that the calculation done apparently "forward" ends
    # showing the rate of change in the interval **leading to** that point. Also
    # the signs are not corrected because both negatives cancel out.
    if($ndata > 1){
        # calc rates
        # $dh_m=($lvl-$lvl_last);
        $dq=($qty-$qty_last); # 
        # 160417: discard all calculations in cm
        # $dq_cm=100*($qty-$qty_last);
        
        # corrected to the proper formula: the number of days in the years of the previous
        # data point is what matters ## 160417: what does that sentence mean, exactly ?
		    # $dt_d=$dy_last*($epoch-$epoch_last)/86400.;  ### this looks wrong now, 
		    #                  what's that dy_last here ?  ### MUST CHECK ###
		    $dt_d=($epoch-$epoch_last)/86400.;  ### epoch replaced ddoy here, not cdyr
		    #                                   ### MUST CONFIRM ###
        $dt_h=$dt_d*24;
        $dt_min=$dt_h*60;
        # print "epoch_last=$epoch_last epoch=$epoch, dt_min=$dt_min\n";
        # $answ = <STDIN>;
        # 160417: replacement of cdyr and ddoy by epoch implies using only units of qph
        # if($dt_min == 0) {
        #     $dhdt_cpd=0;
        #     $dqdt_qph=0;
        #     $dhdt_cpm=0;
        # } else{
        #     $dhdt_cpd=$dh_cm/$dt_d;
        #     $dqdt_qph=$dh_m/$dt_h;
        #     $dhdt_cpm=$dh_cm/$dt_min;
        # }
        if($dt_h == 0) {
            $dqdt_qph=0;   # technically this should be NaN
        } else{
            $dqdt_qph=$dq/$dt_h;
        }
    	  # use deltas above to check for gap
    	  if($dt_min > $thres_gap){	
    		    # there is a gap
    		    printf (STDOUT
  "--> data missing before %4d/%02d/%02d %02d:%02d for %8.0f min, %7.2f days (threshold=%d min)\n",
    			                  $YY,$MM,$DD,$hh,$mm,$dt_min,$dt_d,$thres_gap);
    		    printf (ODGF "data missing before %4d/%02d/%02d %02d:%02d for %8.0f min, %7.2f days\n",
    			                $YY,$MM,$DD,$hh,$mm,$dt_min,$dt_d);
            $ngap++;
            if($dt_min > $gap_max){
                $gap_max = $dt_min;
                $YY_gmax=$YY; $MM_gmax=$MM; $DD_gmax=$DD; $hh_gmax=$hh; $mm_gmax=$mm; 
            }
        } else { 
            # there is no gap
            # update abs extrema if applicable
            # NEW 150907 - only do so if dt_min < $thres_gap,
            #              i.e. do not report extrema calculated over gaps !
            if($dqdt_qph > $dqdt_abs_max) {
                $dqdt_abs_max       = $dqdt_qph;
                $dqdt_abs_max_epoch = $epoch;
                $dqdt_abs_max_qty   = $qty;	
                $dqdt_abs_max_YMDhm	= sprintf("%02d%02d%02d %02d:%02d",$YY,$MM,$DD,$hh,$mm);
            }
            if($dqdt_qph < $dqdt_abs_min) {
                $dqdt_abs_min = $dqdt_qph;
                $dqdt_abs_min_epoch = $epoch;		
                $dqdt_abs_min_qty = $qty;
                $dqdt_abs_min_YMDhm	= sprintf("%02d%02d%02d %02d:%02d",$YY,$MM,$DD,$hh,$mm);
            }
        } # end of checks if there is a gap or not
    	  # check for data overlap
    	  if($dt_min < 0){
            printf (STDOUT
 "\n\n--> negative time interval to %4d/%02d/%02d %02d:%02d for %8.0f min, %7.2f days"
                            $YY,$MM,$DD,$hh,$mm,$dt_min,$dt_d,$thres_gap);
            printf (STDOUT "  -- CHECK FOR DATA OVERLAP!\n",
            printf (ODGF 
 "\n\nnegative time interval to %4d/%02d/%02d %02d:%02d for %8.0f min, %7.2f days"
                          $YY,$MM,$DD,$hh,$mm,$dt_min,$dt_d,$thres_gap);
            printf (ODGF "  -- CHECK FOR DATA OVERLAP!\n",
            $novlap++;
        }
        # for spate detector - define status of current slope CPM
        # if($dhdt_cpm > $spate_thres_up) {
        ### NEW 160417 ### going to qph changes the unit of $spate_thres_up
        if($dqdt_qph > $spate_thres_up) { # qpm -> qph - typo corrected 160419 CV
            $above_thres = 1;
            # do not that now, must use $n_above_thres for previous pt, i.e. *b4* updating it
            # $n_not_above_thres=0;
        } else {
            $above_thres = 0;
            # do not that now, must take decision *before* updating it
            # $n_not_above_thres++;
        }        
        # for spate detector - accumulate status in array
        # spate detector - do check only once enough points accumulated
        # note this is a variation of a minimum detector
        # with the coding as per 130426, @last_thres_vals will always have $n_thres+1 elts
        # once shifting kicks in -- so $last_<>_vals[0] are the last values *before* the
        # <condition> was met and should be used
        push(@last_thres_vals, $above_thres);
        push(@last_YY_vals, $YY);
        push(@last_MM_vals, $MM);
        push(@last_DD_vals, $DD);
        push(@last_hh_vals, $hh);
        push(@last_mm_vals, $mm);
        push(@last_qty_vals, $qty);  ## 160418 JF : qty also stored earlier, in other array, ln 653
        # following two lines RETIRED 160417 and replaced by one just after
        # push(@last_cdyr_vals, $cdyr);
        # push(@last_ddoy_vals, $ddoy);
        push(@last_epoch_vals, $epoch);
        # try something different
        # push(@ttm,$cdyr);
        push(@ttm,$epoch);
        push(@ll,$qty);
                
        # for peak detector - define status of current slope QTY/H
        if($dqdt_qph > $thres_up) {
            $up_met = 1;
        } else {
            $up_met = 0;
        }
        # for peak detector - accumulate slope in array
        push(@last_slopeup_vals, $up_met);
        print "  -- max idx in last_slopeup_vals = $#last_slopeup_vals -- @last_slopeup_vals\n"
            if ($verbose);

        # for through detector - define status of current slope QTY/H
        if($dqdt_qph <= $thres_dn) {
            $dn_met = 1;
        } else {
            $dn_met = 0;
        }
        # for through detector - accumulate slope in array
        push(@last_slopedn_vals, $dn_met);
        print "  -- min idx in last_slopedn_vals = $#last_slopedn_vals -- @last_slopedn_vals\n"
           if ($verbose);
        
        printf (STDOUT "       n>1 %5d   %2d  %2d  %2d\n",
                $ndata,$#dq_local_vals,$#last_thres_vals,$#last_in_spate_vals) if($verbose_stack);
        # for spate detector: this test ensures that at least as many data points already 
        # have been read, as is required by $n_recent_to_consider
        if($ndata > $n_recent_to_consider) {
            # First algo tested
            # following check only returns 1 if **all** elements in last_thres_vals 
            # are 1 (above threshold), including the current one just read. Thus it
            # will trigger on the first point that makes $n_thres_sup consecutive above threshold
            # $in_spate=1;
            # for($i=0;$i<$n_recent_to_consider;$i++){
            #	    $in_spate *= $last_thres_vals[$i];
            # }
            ## try algo "3 out of 4" - assuming n_spate_thres is already 4
            $sum=0;
            for($i=0;$i<$n_recent_to_consider;$i++){
                $sum += $last_thres_vals[$i];
            }
            # get local change of level **in mm* - need current + previous 4 (not 3) points
            # Note! I don't understand the '+2' (and why not just '+1') - this is *bad*
            # pirate !#  if($ndata > $n_recent_to_consider){             #BUG-R#
                # BUG-R# : (took off the "+3" on 160417 that was in there)  ### MUST CHECK ###
                # $dq_local = 1000.*($dq_local_vals[$n_recent_to_consider]-$dq_local_vals[0]);
                ### 1000 multipliers was to get mm, removed 160417  ### MUST CHECK ###
                $dq_local = ($dq_local_vals[$n_recent_to_consider]-$dq_local_vals[0]);
            # pirate !# }
            # print "highest index in dq_local_vals = $#dq_local_vals\n"; # says 3 when
            #      $n_spate_thres_up=4
            # i.e. 3 is the highest for a total of 4 elements (as expected)
            # added 140304 requirement that 1st and last are 1
            # this is to avoid triggering on "zeroes-1-1-1-zeroes"
            # pirate !# 160422 JF comments:
            # LOCAL COMMENT EVOLVES TO GENERAL DISCUSSION OF SCRIPT's APPROACH 
            # 1. dq compares current point with point at start of look-back interval,
            #    $n_recent_to_consider points in the past
            #    -> is this a good trigger in principle ? Why probe exactly the same #pts as
            #       for checking in_spate status ?
            # 2. related to 1. : TODO: must define criterium for setting the time of start
            #    of the spate. Now uses 1st point in look-back range
            # 3. ideas in 1. and 2. would be fine assuming that one has in mind that "the
            #    start of the look-back has to be the start of the spate".
            #    In other words, this is the sams as to ask "how far to look into the data
            #     to be certain a spate has started ? - $n_recent_to_consider"
            #    But if now $n_recent_to_consider is made arbitrary large (say going from
            #     4 to 10 points) with the idea "to make sure it works", then the
            #    logics above is broken: the parameter $n_slope_up_above_thres is tied to
            #     the noisiness of the signal (or how sensitive we want the spate
            #    detection to be given the actual noise level), and the ***test will be
            #     passed the same, even if $n_recent_to_consider is made larger***.
            #    An unfortunate consequence will be that the time of start of spate will
            #     be artificially pushed in the past, i.e. will be wrong.
            # 4. Pt. 3. illustrates that $n_recent_to_consider is asymetric: if too small,
            #     some spates are missed, but start time will be right; the
            #    art is in finding the value where spates are not missed *and* their time
            #     is still right
            # 5. Finally, the 'fuzzy argument' to request that "M out of N recent incl 1st
            #     and last are in spate" **necessarily implies that the start time
            #    is not exactly at the first element** - the start time will be a function
            #     of the value of $sum/$n_recent_to_consider. Exactly the first
            #    when the ratio is one (they are all in spate), and later if < 1. A function
            #     could be guessed ... 
            # 6. ... but if the spate is real, the simplest is to *fit the first points and
            #     look for the intercept with the baseline*. Ok, this could have
            #    been a spate detector on its own, like : find the peaks, work backwards to
            #     find backwards when they start. It obviously gets complicated too,
            #    when the "shape" of the start of *any* spate has to be taken into account..
            #     This shape is probably cave, site, base-line, input ... dependent!
            # 7. And this is why this code was not started initially this way. It was felt
            #     that the data alone should say "I think I am up to something",
            #    *pior* any evidence of a large peak
            #    s
            if($sum >= $n_slope_up_above_thres && $last_thres_vals[0] == 1 
                         && $last_thres_vals[$n_recent_to_consider-1] == 1
                         && $dq_local >= $dq_local_min){
                $in_spate=1;
            } else {
                $in_spate=0;
            }
            # pirate !#
            push(@last_in_spate_vals, $in_spate);
            printf (STDOUT "    recent %5d   %2d  %2d  %2d\n",
                    $ndata,$#dq_local_vals,$#last_thres_vals,$#last_in_spate_vals)
                        if($verbose_stack);
            # must wait enough additional points are collected, so that one can test
            # according to parametrization in DB
            if($ndata > $n_recent_to_consider+$n_not_in_spate_req) {
                # sum over recent (but not current!) points,
                # to check that they were *not* in_spate
                $sum_ris=0;
                for($i=0;$i<$n_not_in_spate_req;$i++){
                    $sum_ris += $last_in_spate_vals[$i];
                }
                # i.e. $sum_ris should remain 0 if none of them was in_spate

                # pirate !#
                # ##### check if new spate ###  remember data now goes *forward* in time
                # if($in_spate && !$in_spate_last 
                #              && !$in_spate_last_but1 
                #              && !$in_spate_last_but2){
                #              # && $n_not_above_thres >= $n_not_above_thres_req) {
                # pirate !#

                ##### check if new spate ###  remember data now goes *forward* in time
                if($in_spate && $sum_ris == 0) {
                    $new_spate=1;
                    $nspate++;
                    $peak_passed=0;
                    # if($nspate == 87){
                    #   	$verbose=1;
                    # } else {
                    # 	  $verbose=0;
                    # }
                } else {
                    $new_spate=0;
                }
                # if new_spate, conclude scanning for qty_max and start new scan
                # (means peak must have been passed, restart!)
                # CONT HERE
                if($new_spate){
                    # pirate !# The next question is "when did it start ?"
                    # pirate !# Scan 'recent' range bacb and take first idx which is in_spate
                    # pirate !# print "\nOK, in spate now !\n last_qty_vals=@last_qty_vals\n";
                    # pirate !# print " last_thres_vals=@last_thres_vals\n";
                    # pirate !# print " dq_local_vals=@dq_local_vals\n";
                    # pirate !# print " last_datetime_vals=@last_datetime_vals\n";
                    # pirate !# for @last_thres_vals, [$n_recent_to_consider] = current,
                    # pirate !#      so start at -1 with "first before current"
                    for($i=$n_recent_to_consider-1;$i>=0;$i--){
                        $sp_idx=$i;
                        if($last_thres_vals[$i] == 0){
                            $sp_idx=$i+1;
                            last;
                        }
                    }
                    $pt_id = $ndata-$n_recent_to_consider+$sp_idx;
                    print "\nOK, new spate: ndata=$ndata, sp_idx=$sp_idx, pt_id=$pt_id\n"
                        if($verbose_stack);
                    print "qty=$qty, qty2_current=$last_qty_vals[$n_recent_to_consider-1]\n"
                        if($verbose_stack); 
                    print "qty2@sp_idx=$last_qty_vals[$sp_idx] (assay last idx=$#last_qty_vals)\n"
                        if($verbose_stack);
                    print "qty1=$dq_local_vals[$sp_idx+1], dt=$last_datetime_vals[$sp_idx+1]\n"
                        if($verbose_stack);
                    # $qty_delta = $qty_max - $qty;
                    # $ddoy_delta = $ddoy_max - $ddoy;
                    # if($ddoy_delta < 0) {
                    #     $ddoy_delta += &dysize($YY-1);
                    # }
                    # set references for ***start of spate** (using "at last min" was *wrong*)
                    $qty_base=$last_qty_vals[0];
                    # $ddoy_base=$last_ddoy_vals[0];  ### NOTE 160417: replacing ddoy with
                                                      # epoch changes the units by factor 86400 !
                    $epoch_base=$last_epoch_vals[0];
                    # reminder for self on 160417: tsls_d = time since last spate (days)
                    printf (STDOUT "   recent+ %5d   %2d  %2d  %2d\n",
                            $ndata,$#dq_local_vals,$#last_thres_vals,$#last_in_spate_vals)
                                if($verbose_stack);
                    if($nspate == 1){
                        $tsls_d=0;
                        $tsls_d_max=0;
                    } else {
                        # $tsls_d=$ddoy_base-$last_spate_ddoy;
                        $tsls_d = ($epoch_base-$last_spate_epoch)/86400.;
                        ## Obsoleted by replacing ddoy with epoch ?
                        ## This was adding days in last year once going into next
                        # if($tsls_d < 0) {
                        #     $tsls_d += &dysize($YY-1);
                        # }
                        ### NOT SURE ABOUT THIS ONE THEN        ### CHECK THIS OUT ###
                        ### 160418 JF: this is legit: update extremum if applicable
                        if($tsls_d > $tsls_d_max) {
                            $tsls_d_max = $tsls_d;
                            ### Odd that I did not want to record *when* this max was found ..
                        }
                    }
                    # output in two steps: 1 (here) - the start of the spate
                    #  (next, 2: when peak found_)
                    if($nspate > 1){
                        printf (STDOUT "\n");
                        printf (ODSF   "\n");
                        printf (ODSLF  "\n");
                    }  # 160414 moved output of headers (legends) to top of files at user's
                       # request # else { print headers }

                    printf (STDOUT
   "\nNew spate \# %5d (pt %7d)\n at qty=%+10.3f on %4d%02d%02d %02d%02d (after %6.3f days) ",
                                    $nspate,$ndata,
                                    $last_qty_vals[0],
                                    $last_YY_vals[0],$last_MM_vals[0],$last_DD_vals[0],
                                    $last_hh_vals[0],$last_mm_vals[0],$tsls_d);
                    printf (ODSF "%5d %7.3f  %10d %+8.4f  ",
                                  $nspate,
                                  $tsls_d, $last_epoch_vals[0],$last_qty_vals[0]);
                    # printf (ODSF "Legend:\nnspat tsls_d  _____cdyr______ __hT(m)_  \n");
                    
                    ### debug 160419 JF
                    # for($i=0;$i<=$#last_YY_vals;$i++){
                    #     printf (ODSLF 
                    # "ns\# %5d (pt %07d): %4d%02d%02d %02d:%02d  %7.3f  %10d %+10.4f  \n",
                    #                   $nspate,$ndata,
                    #                   $last_YY_vals[$i],$last_MM_vals[$i],$last_DD_vals[$i],
                    #                   $last_hh_vals[$i],$last_mm_vals[$i],
                    #                   $tsls_d, $last_epoch_vals[$i],$last_qty_vals[$i]);
                    # }
                                  
                    printf (ODSLF
                    "ns\# %5d (pt %07d): %4d%02d%02d %02d:%02d  %7.3f  %10d %+10.4f  ",
                                  $nspate,$ndata,
                                  $last_YY_vals[0],$last_MM_vals[0],$last_DD_vals[0],
                                  $last_hh_vals[0],$last_mm_vals[0],
                                  $tsls_d, $last_epoch_vals[0],$last_qty_vals[0]);
                    # printf (ODSFL
# "Legend:\nnspat (pt _____ID): YYYY MM DD hh mm  tsls_d  _____cdyr______ __hT(m)_  ");
                    # printf (ODTF "%+8.4f\n",
                    # 	$qty_delta);
                    # *do not* reset min to current value, so as to scan for new max
                    #  from the min -- this was wrong
                    # 140305: why?
                    # &setmax();

                    $last_spate_epoch=$epoch_base;
                } # if newspate
                shift(@last_in_spate_vals);
            } # if($ndata > $n_recent_to_consider+$n_not_in_spate_req)
            # safer now to clean arrays at the bottom
            shift(@last_thres_vals);
            shift(@last_YY_vals);
            shift(@last_MM_vals);
            shift(@last_DD_vals);
            shift(@last_hh_vals);
            shift(@last_mm_vals);
            shift(@last_qty_vals);
            # shift(@last_cdyr_vals);
            # shift(@last_ddoy_vals);
            shift(@last_epoch_vals);
            # Note! I don't understand the '+2' (and why not just '+1') - this is *bad*
            # if($ndata > $nspate_thres_up+5){
        		shift(@dq_local_vals);
            shift(@last_datetime_vals);  
            # }
        } # if ndata > n_recent_to_consider
        
        ## something different - un-dot-product -> stupid, dynamic range will mess it up
        if($ndata > 8){
            # $x1=$tt[5]-$tt[0];
            # $x2=$tt[7]-$tt[5];
            # $y1=$ll[5]-$ll[0];
            # $y2=$ll[7]-$ll[5];
            # $L1=sqrt($x1*$x1+$y1*$y1);
            # $L2=sqrt($x2*$x2+$y2*$y2);
            # $cos_t=($x1*$x2+$y1*$y2)/($L1*$L2);
            # $theta=acos($cos_t);
            ## second try -- still no good, even really bad
            # $dx1=365*($ttm[5]-$ttm[0]);
            # $dx2=365*($ttm[7]-$ttm[5]);
            # # print "@ttm\n";
            # $dy1=$ll[5]-$ll[0];
            # $dy2=$ll[7]-$ll[5];
            # die("Error at ndata=$ndata crdy=$cdyr: dx1=0\ndie\n") if ($dx1 == 0);
            # die("Error at ndata=$ndata crdy=$cdyr: dx2=0\ndie\n") if ($dx2 == 0);
            # $sl1=($dy1)/($dx1);
            # $sl2=($dy2)/($dx2);
            # $DSL=$sl2-$sl1;
            # printf (STDOUT 
  # "ndata=%6d  dx1=%.3f dx2=%.3f   dy1=%.4f dy2=%.4f  sl1=%9.2e sl2=%9.2e  DSL=%9.2e\n",
            #                 $ndata,$dx1,$dx2,$dy1,$dy2,$sl1,$sl2,$DSL);
            ## third try - average slopes.. -- not any better ! leave it in for now
            $ASL1=0;
            $ASL2=0;
            for($i=0;$i<7;$i++){
                $dxi=365*($ttm[$i+1]-$ttm[$i]);
                $dyi=$ll[$i+1]-$ll[$i];
                die("Error at ndata=$ndata epoch=$epoch: dxi=0 for i=$i\ndie\n")
                    if ($dxi == 0);
                $sli=($dyi)/($dxi);
                if($i<5){
                    $ASL1 += $sli;
                } else {
                    $ASL2 += $sli;
                }
            }
            $ASL1 /= 5;
            $ASL2 /= 2;
            if($ASL1 == 0) {
                $DSL=0;
            } else {
                $DSL=($ASL1-$ASL2)/$ASL1;
            }
            # printf (STDOUT "ndata=%6d  ASL1=%9.2e ASL2=%9.2e  DSL=%9.2e\n",
            #                 $ndata,$ASL1,$ASL2,$DSL);
            shift(@ttm);
            shift(@ll);
        }
        
        ## peak detection
        # Important: +1 required here to accumulate enough values in @last_slopeup_vals
        if($ndata > $n_thres_up+1) {
            # for peak scanning - trigger on slope change from
            #  ($n_thres_up consecutive +) to (-) after a minimum
			
            # following check only returns 1 if **all but the last** elements in
            # last_slopeup_vals are 1 (cond met)
            $peak_cond_met=1;  ## 160418 JF: a bit of a misnomer: this is saying
                               ## "all points so far are still going up"
                               ## - a condition to be met up to the peak
            # important: do *not* use current point ! we want it have a neg slope so
            #            peak is hard-coded  @ last point ..
            # yes, yes, yes.. # array elements increased in test above,
            #                   hence no '-1' below (and line above still holds)
            for($i=0;$i<$n_thres_up;$i++){
                $peak_cond_met *= $last_slopeup_vals[$i];
            }
            # then clean array at the bottom
            shift(@last_slopeup_vals);
            printf (STDOUT
 " ndata=%5d  qty=%+10.4f  dqdt_qph=%+8.4f  peak_cond_met=%1d nspate=%1d  -- peak conds: ",
                            $ndata,$qty,$dqdt_qph,$peak_cond_met,$nspate)
                                if ($verbose);
            # 160417 - what is this test ? Ensuring that it is not going up ? 
            ## 160418 JF NO ! this is the first point where the slope goes below
            ##                threshold - it **is the top of the peak**
            if($dqdt_qph <= $thres_up && $peak_cond_met == 1 
                                      && $nspate > 0){
                printf (STDOUT
 "\n\n >> passed pk at: ndata=%5d qty=%10.3f, last_setmax_call_: ndata=%5d qty=%10.4f",
                        $ndata,$qty,$last_setmax_call_ndata,$last_setmax_call_qty)
                           if($verbose_peaks);
                printf (STDOUT " passed ++++++") if ($verbose);
                $is_max=1;
                $qty_delta = $qty_max - $qty_base;
                if($qty_delta > $dq_max){
                    $dq_max = $qty_delta;
                }
                # $ddoy_delta = $ddoy_max - $ddoy_base;
                $epoch_delta = $epoch_max - $epoch_base;  ### units are seconds
                $days_delta = $epoch_delta/86400.;        ### units are days
                # not longer needed ,this was to add #days in prev. years when moving on
                #  into the next
                # if($ddoy_delta < 0) {
                #     $ddoy_delta += &dysize($YY-1);
                # }
                # now that peak was found, can close up entry on new spate
                    # output in two steps: 1 (above) - the start of the spate; 2 (here):
                    #  when peak found
                # 160420 JF: problems?
                # 1) <>_max values were not set right here at peak !?! - no, this is done
                #       only in routine setmax();
                #    but every new point is tested for $qty>$qty_max. If yes, setmax()
                #    is invoked.
                #    Note1 this is independent of checking for absolute extrema, which
                #          is done just after reading ea data pt
                #    Note2 this is also independent of the test above...
                #    => should setmax() be invoked prior to print out then ?
                # 2) forgot ...
                # &setmax(); ## well, maybe not: condition where *peak is passed* maybe
                #            ## .. after max ! 
                printf (STDOUT
  "\n to qty=%+10.3f on %4d%02d%02d %02d%02d (dq=%10.3f over %6.3f days)+",
                        $qty_max,$YY_max,$MM_max,$DD_max,
                        $hh_max,$mm_max,$qty_delta,
                        $days_delta);        ### NOTE: $days_delta was $ddoy_delta
                # reset min to here, so as to look for next min down from the peak
                if($peak_passed == 1){
# printf (STDOUT
# "\n                                                                            ");
# printf (ODSLF
# "\n                                                                            ");
printf (ODSLF
 "\n                                                                        ");
# printf (ODSLF
# "\n                                                                            ");
                }
                # 141021: comment for now ("0,>1 nspates" problem)
                # printf (ODSF "%15.10f %+8.4f  %+7.3f  %6.3f  ",
                # 	$epoch_max,$qty_max, $qty_delta,$ddoy_delta);
                printf (ODSLF "pk: %4d%02d%02d %02d:%02d %+10.4f  %+10.3f  %8.3f",
                               $YY_max,$MM_max,$DD_max,$hh_max,$mm_max,
                               $qty_max, $qty_delta,$days_delta);
                               ### NOTE: $days_delta was $ddoy_delta
                $peak_passed=1;
                # printf (ODSFL "pk: _____epoch______ hTmax(m)  _dhT(m)  _Ddays");
                # reset the min at the max, so can scan for new min from now on ..
                &setmin();
            } else {
                printf (STDOUT " failed --\n")
                   if ($verbose); ## 160718 JF: should also tell OSLF ?
                $is_max=0;
            }
        } # if ndata > n_thres_up+1
        
        ## through detection
        # Important: +1 required here to accumulate enough values in @last_slopedn_vals
        if($ndata > $n_thres_dn+1) {
            # for through scanning - trigger on slope change from
            #  ($n_thres_dn consecutive +) to (-) after a minimum
      
            # following check only returns 1 if **all but the last** elements in
            #  last_slopedn_vals are 1 (cond met)
            $through_cond_met=1;
            # important: do *not* use current point ! we want it have a neg slope so
            #            peak is hard-coded  @ last point ..
            # yes, yes, yes.. # array elements increased in test above, hence no '-1'
            #                   below (and line above still holds)
            for($i=0;$i<$n_thres_dn;$i++){
                $through_cond_met *= $last_slopedn_vals[$i];
            }
            # then clean array at the bottom
            shift(@last_slopedn_vals);
            printf (STDOUT
" ndata=%5d  qty=%+10.4f  dqdt_qph=%+8.4f  through_cond_met=%1d nspate=%1d  -- through conds: ",
                            $ndata,$qty,$dqdt_qph,$through_cond_met,$nspate)  if ($verbose);
            # 160417 looks like a through condition passed here
            if($dqdt_qph <= $thres_dn && $peak_cond_met == 1 && $nspate > 0){ #BUG9#
                #BUG9# : should this be "through" and not "peak" ? 160418 JF
                printf (STDOUT
"\n\n >> passed th at: ndata=%5d qty=%10.3f, last_setmin_call_: ndata=%5d qty=%10.4f",
                        $ndata,$qty,$last_setmin_call_ndata,$last_setmin_call_qty)
                             if($verbose_peaks);
                printf (STDOUT " passed ++++++") if ($verbose);
                $is_min=1;
                # $qty_delta is unique to peaks in spates - comment out here
                $qty_delta_dn = $qty_min - $qty_max;     # min - max  is a feature of a
                                                         # 'through'
                                                         # 160418 JF - check signs
                # if($qty_delta > $dq_max){
                # 	  $dq_max = $qty_delta;
                # }
                $epoch_delta = $epoch_min - $epoch_max;  # min - max  is a feature of a 
                                                         # 'through' but is it right
                                                         #  for time #BUG# ?
                                                         ### MUST CHECK ###
                $days_delta = $epoch_delta/86400.;
                $days_delta_dn = $days_delta;       #### added 160417 as it seemed to be
                                                    # missing, and is invoked in next printf stmnt
                # if($ddoy_delta < 0) {
                #     $ddoy_delta += &dysize($YY-1);
                # }
                
                # now that through was found, can close up entry on new spate
                # output in two steps: 1 (above) - the start of the spate; 2 (here): when pk fnd
                # 160420 JF added setmin() so that printed values are current ones
                # &setmin(); ## well, maybe not: condition where *th is passed* maybe .. after min !
                printf (STDOUT
                 "\n to qty=%+10.3f on %4d%02d%02d %02d%02d (dq=%10.3f over %6.3f days)-",
#                    $qty_max,$YY_max,$MM_max,$DD_max,
#                    $hh_max,$mm_max,$qty_delta_dn,$days_delta_dn);  ## WTH ?!?
                                $qty_min,$YY_min,$MM_min,$DD_min,
                                $hh_min,$mm_min,
                                $qty_delta_dn,$days_delta_dn);
                # reset min to here, so as to look for next min down from the peak
                # if($through_passed == 1){
# printf (STDOUT "\n                                                                            ");
# printf (ODSLF "\n                                                                            ");
printf (ODSLF "\n                                                                        ");
                # }
                # 141021: comment for now ("0,>1 nspates" problem)
                # printf (ODSF "%15.10f %+8.4f  %+7.3f  %6.3f  ",
                # 	$epoch_min,$qty_min, $qty_delta_dn,$ddoy_min);
                printf (ODSLF "tr: %4d%02d%02d %02d:%02d %+10.4f  %+10.3f  %8.3f",
                              $YY_min,$MM_min,$DD_min,$hh_min,$mm_min,
                              $qty_min, $qty_delta_dn, $days_delta_dn);
                # printf (ODSFL "tr: _____epoch______ hTmax(m)  _dhT(m)  ddoy_at_min\n");
                $through_passed=1;
                # reset the max at the min, so can scan for new max from now on ..
                &setmax();
            } else {
                printf (STDOUT " failed --\n") if ($verbose);
                $is_min=0;
            }
        } # if ndata > n_thres_dn+1
        
    } # ndata > 1

    # printing to other data files looks like a sinecure now..
    # Except that any new field added to ODDF will require updating ReadMoti.C
    # and break backward compatibility !
    printf (ODF "%02d/%02d/%4d %02d:%02d, %+10.4f, %10d,  ",   # %12.7f, %7.3f, ",
                $MM,$DD,$YY,$hh,$mm,$qty,$epoch);             # ,$cdyr-$YY0,$ddoy); # $cdoy %5.1f
    printf (ODDF "%4d %02d %02d %02d %02d  %+10.4f  %10d  ",     # %15.10f %12.7f %7.3f  ",
                 $YY, $MM, $DD, $hh, $mm,  $qty,    $epoch);     # ,$cdyr,$cdyr-$YY0,$ddoy);
    # printf (ODDF "Legend:\nMM DD YYYY hh mm  __hT(m)_ _____cdyr______ __cdyr-YY0__ __ddoy_  ");
	
    # printf (ODF  " %+9.5f, %+9.5f",$dqdt_qph,$dhdt_cpm);
    printf (ODF  "%+9.5f,",$dqdt_qph);
    printf (ODDF "%+9.5f  ",$dqdt_qph);
    # printf (ODDF " _dqdt_qph dhdt_cmpm");
  
    # printf (ODF  " , %+9.2E, %1d, %1d, %1d, %1d, %1d, %1d, %1d\n",
    # $DSL,$up_met,$is_max,$dn_met,$is_min,$above_thres,$n_not_above_thres,$new_spate);
    # printf (ODDF "  %+9.2E  %1d %1d  %1d %1d  %1d %1d %1d\n",
    # $DSL, $up_met,$is_max,$dn_met,$is_min,$above_thres,$n_not_above_thres,$new_spate);
  
    printf (ODF  " %+9.2E, %1d, %1d, %1d, %1d, ",$DSL,$up_met,$is_max,$dn_met,$is_min);
    printf (ODDF "%+9.2E  %1d %1d  %1d %1d  ",$DSL, $up_met,$is_max,$dn_met,$is_min);
    # printf (ODDF "  _DeltaSL_  For here on a galore of 1/0 flags, in this order:\n");
    # printf (ODDF "up_met is_max  dn_met is_min  ");
  
    printf (ODF  "  %+10.4f, ",$dq_local);
    # pirate !# printf (ODF  "  %1d,  %1d, %1d, %1d, %1d,",
    # $above_thres,$in_spate,$in_spate_last,$in_spate_last_but1,$in_spate_last_but2);
    printf (ODF  "  %1d,  %1d,",$above_thres,$in_spate);
    printf (ODF  "  %4d, %1d\n",$n_not_in_spate,$new_spate);

    printf (ODDF "%+10.4f  %+10.4f  ",$dq, $dq_local);
    # printf (ODDF "  +7.1f: dq_local ");
    # pirate !# printf (ODDF "  %1d  %1d %1d %1d %1d",
    # $above_thres,$in_spate,$in_spate_last,$in_spate_last_but1,$in_spate_last_but2);
    printf (ODDF "%1d %1d  ",$above_thres,$in_spate);
    # printf (ODDF
    # "  above_thres in_spate in_spate_last in_spate_last_but1 in_spate_last_but2");
    printf (ODDF "%4d %1d\n",$n_not_in_spate,$new_spate);
    # printf (ODDF "  n_not_in_spate new_spate\n--- End of Legend ---\n");


    # put here all updates that must be done before moving to the next point        
    $YY_last=$YY;
    $epoch_last=$epoch;
    $qty_last=$qty;
    $dqdt_qph_last=$dqdt_qph;
    $in_spate_last_but2=$in_spate_last_but1;
    $in_spate_last_but1=$in_spate_last;
    $in_spate_last=$in_spate;
    # if($above_thres == 1) {
    #   	$n_not_above_thres=0;
    # } else {
    #   	$n_not_above_thres++;
    # }        
    if($in_spate == 1) {
        $n_not_in_spate=0;
    } else {
        $n_not_in_spate++;
    }        

} # while (<IDF>) -- loop over data lines in .tod file


# in case last spate's peak did not make it in the current data
printf (ODSF "\n");
printf (ODSLF "\n");

close(IDF);
close(ODF);
close(ODDF);
close(ODSF);
close(ODSLF);
close(ODGF);
# close(ODTF);

printf (STDOUT "\n\nSummary:\n%d points processed in %s\n",$ndata,$tnam);
printf (OSF    "Summary file for ppr.pl processing of %s\n\n%d points processed\n",
        $tnam,$ndata);
$msg1=sprintf ("%d gaps found\n  threshold = %d min\n",$ngap,$thres_gap);
if($ngap > 0) {
    $msg2=sprintf ("  longest %.2f days into %04d%02d%02d %02d:%02d\n",
                  $gap_max/1440.,$YY_gmax,$MM_gmax,$DD_gmax,$hh_gmax,$mm_gmax);
} else {
    $msg2="  --no data--\n";
}
$msg3=sprintf ("  -> see .gap file\n");
$msg=$msg1 . $msg2 . $msg3;
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("%d possible data overlaps found\n",
              $novlap);
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg1=sprintf("%d spate/s found\n",$nspate);
$msg2=sprintf("  criteria (all inclusive):\n");
$msg3=sprintf(
      "  - dqdt_qph >= %.3f for %d of %d recent, consec. pts (incl. first and last)\n",
              $spate_thres_up, $n_slope_up_above_thres, $n_recent_to_consider);
$msg4=sprintf("  - %d consecutive preceding points are not in spate\n",
              $n_not_in_spate_req);
$msg5=sprintf("  - change of quantity between first and last in range >= %.4f\n",
              $dq_local_min);
$msg6=sprintf("  longest ivl between spates = %.2f days, highest ampl = %.2f qty\n",
              $tsls_d_max, $dq_max);
$msg7=sprintf("  -> see .spt file (.sptl for long format)\n");
$msg=$msg1 . $msg2 . $msg3 . $msg4 . $msg5 . $msg6 . $msg7;
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("absolute extrema in qty in this data:\n");
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg1=sprintf ("  min: %+10.3f qty  at epoch=%10d [%s]\n",
              $qty_abs_min, $qty_abs_min_epoch, $qty_abs_min_YMDhm);
$msg2=sprintf ("  max: %+10.3f qty  at epoch=%10d [%s]\n",
              $qty_abs_max, $qty_abs_max_epoch, $qty_abs_max_YMDhm);
$msg=$msg1 . $msg2;
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("absolute extrema in rate of change of qty in this data:\n");
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg1=sprintf ("  min: %+10.3f qph  at epoch=%10d [%s] (qty=%+10.3f)\n",
              $dqdt_abs_min, $dqdt_abs_min_epoch, $dqdt_abs_min_YMDhm, $dqdt_abs_min_qty);
$msg2=sprintf ("  max: %+10.3f qph  at epoch=%10d [%s] (qty=%+10.3f)\n\n",
              $dqdt_abs_max, $dqdt_abs_max_epoch, $dqdt_abs_max_YMDhm, $dqdt_abs_max_qty);
$msg=$msg1 . $msg2;
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);

close(OSF);


############# this is the end of main ---- procedure definitions follow ###############


#########################################################################################
# Note added 160416 JF on date and time formats (DTF)s (aka datetime)
# 
#     I aim to use a DTF that is portable and rational for scientific use (hum).
# I just looked up standards and found that for the exceptions of cc = centiseconds, the
# usage of which is legacy from SNO, the format - or representation - of date+time I have
# been using is the W3C DTF standard (from ISO 8601). For a good intro, and the standard,
# see: 
# https://www.hackcraft.net/web/datetime/
# http://www.iso.org/iso/home/standards/iso8601.htm (official but they want $$ from you)
# https://en.wikipedia.org/wiki/ISO_8601 (free, contemplate donating every now and then)
# 
# 
# Ordinal dates 'YYYY-DDD' or 'YYYYDDD' provide a simple form for occasions when the 
# arbitrary nature of week and month definitions are more of an impediment than an aid,
# for instance, when comparing dates from different calendars. As represented above, 
# [YYYY] indicates a year. [DDD] is the day of that year, from 001 through 365 (366 in
# leap years). For example, "1981-04-05" is also "1981-095"
# 
# Ordinale dates are attractive as the unit of one day is a lot more constant than a year.
# a) Still, leap years must be taken into account:
#
# Selon Wikipedia [https://fr.wikipedia.org/wiki/Année_bissextile]:
# Depuis l'ajustement du calendrier grégorien, l'année sera bissextile (elle aura 366 jours):
#     si l'année est divisible par 4 et non divisible par 100, ou
#     si l'année est divisible par 400.
# Sinon, l'année n'est pas bissextile (elle a 365 jours).
#
# my interpretation of this logic is:
#     $mydy = 365;
#     $mydy = 366 if( ( (($YY % 4) == 0) && ($YY % 100) ) || (($YY % 400) == 0) ) ;
# whereas the script below found on the web ("Gnarfer from hell") uses ($y=$YY):
#     $yr = 366 if((($y % 4) == 0) && ( ($y % 100) || (($y % 400)==0) )) ;
# so I tested both from 1800 to 2505 and they always return identical values.
# This is because the last clause (%400) always verifies the first (%4)
#
# b) besides, if the data covers more than one year, some time zero must be defined,
# which would naturally be the first day of data .. but rundata/db time spans are
# read before any data. Plus, different data files might have different initial times.
# And if the output files end up being used for comparisons, they must have the same t0.
#
#
# THE EPOCH IT IS
# 
# So, after quite some reading off the net, I decided to follow the advice that there is
# no better time reference than the 'epoch' - even it if might be machine-dependent.
# A very common package is DateTime, from which these two functions will suffice:
#     my $dtp = DateTime->new(
#         year       => 1988,
#         month      => 3,
#         day        => 5,
#         hour       => 12,
#         minute     => 00,
#         second     => 47,
#         nanosecond => 500000000,
#         time_zone  => 'America/Chicago',
#     );
# and:
#     $asbolute_time_axis_in_seconds_since_midnight_Jan_1_1970 = $dtp->epoch();
#
# or in simplified form:
#     $YY=1965; $MM=9; $DD=3; $hh=9; $mm=30;
#     $dts = DateTime->new(year => $YY, month => $MM, day => $DD, hour => $hh, min => $mm);
#     $beuhs = $dts->epoch();
# 


### obsoleted 160417 - sorry Gnarfer fH (next few blocks, not all)
########################################################################################
# The following from my standard script for DTF, turned into subs for cl2dat>ppr.pl :
#
# print "Enter year YYYY: ";
# $YY=<STDIN>;
# print "Enter month  MM: ";
# $MM=<STDIN>;
# print "Enter day    DD: ";
# $DD=<STDIN>;
#
# $cdoy=&DoYR($DD,$MM,$YY);
# $dy=&dysize($YY);
# $cdyr=$YY+$cdoy/$dy;
#
# print "\ncurrent day of the year : $cdoy\n";
# print "# days in current year  : $dy\n";
# print "Digital year coordinate : $cdyr\n\n";
#
# this from a script found on the web (Time.pl)
# pretty well debugged version Oct 2000 JF
########################################################################################
#
# Copyright (c) Ove Ruben R Olsen (Gnarfer from hell)
#
# Permission to use, copy, and distribute this software and its
# documentation for any purpose and without fee is hereby granted,
# provided that the above copyright notice appear in all copies and that
# both that copyright notice and this permission notice appear in
# supporting documentation.
# This also apply your own incarnations of any or all of this code.
# If you use portions of this code, you MUST include a apropriate notice
# where you "stole" it from.
#
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# Email:  Ruben@uib.no 
#
#
# THIS WORK IS DEDICATED TO Anne Marit Fjeldstad the one and only. 
#
################################################################################
#                                                                              #
#                   This is ABSOLUTELY FREE SOFTWARE.                          #
#                                                                              #
#                                                                              #
#          BUT: If you find this software usefull, please contribute           #
#               aprox 10 USD to your country's cancer research.                #
#                                                                              #
#                                                                              #
#                             END OF NOTICE                                    #
#                                                                              #
################################################################################
# @mdays   = ( '31', '28', '31', '30', '31', '30', 
#	      '31', '31', '30', '31', '30', '31' ) ;
#  DoYR (day,month,year)  => daynumber in year  || -1

sub DoYR { # day, month, year  ### obsoleted 160417 - sorry Gnarfer fH
  local ($day,$mon,$year,$i,$j) = (@_[0],@_[1],@_[2],0,0);
  return -1 if ($day < 1);
  # this check added 160417 JF
  return -1 if (($mon < 1) || ($mon > 12));
  return -1 if (($day > $mdays[$mon-1]) && (&dysize($year) == 365));
  return -1 if (($day > 29) && ($mon == 2) && (&dysize($year) == 366));
  # add extra day if past Feb and in a leap year
  # THIS NEEDS TO BE TESTED - I HAD A CASE WHERE THE  () ? : CONSTRUCT FAILED
  $j = (($mon > 2) && ( &dysize ($year) == 366)) ? 1 : 0 ;
  for($i=1 ; $i < $mon ; $i++) { $j += $mdays[$i-1] ; }
  return ($j + $day ) ;
}

# dysize (year)  => number of days in year || -1  ### obsoleted 160417 - sorry Gnarfer fH
sub dysize { 
  local($y,$yr) = (@_[0],365) ;
  return -1 if ($y < 0 ) ;
  return 347 if ($y == 1752);
  # $y += 1900 if($y < 1970) ;
  # original from Gnarfer :
  # $yr = 366 if((($y % 4) == 0) && ( ($y % 100) || (($y % 400)==0) )) ;
  # my version JF 160417 [proven identical to above, but syntactically closer to wiki]:
  $yr = 366 if( ( ( ($y % 4) == 0) && ($y % 100) ) || (($y % 400)==0) ) ;
  return  $yr ;
}

# set current values to new maximum - ## 160418 JF typically done at a through,
# as the point is to get, from there on, the next local maximum
sub setmax {
	$MM_max=$MM;
	$DD_max=$DD;
	$YY_max=$YY;
	$hh_max=$hh;
	$mm_max=$mm;
	$qty_max=$qty;
	# $ddoy_max=$ddoy;
	# $cdyr_max=$cdyr;
	$epoch_max=$epoch;
}

# set current values to new minimum - ## 160418 JF typically done at a peak,
# as the point is to get, from there on, the next local minimum
sub setmin {
	$MM_min=$MM;
	$DD_min=$DD;
	$YY_min=$YY;
	$hh_min=$hh;
	$mm_min=$mm;
	$qty_min=$qty;
	# $ddoy_min=$ddoy;
	# $cdyr_min=$cdyr;
	$epoch_min=$epoch;
}

# make the following work for any file handle !
# snippet from 
# http://stackoverflow.com/questions/13702278/send-file-handle-as-argument-in-perl
# 
# use strict;
# use warnings;
# 
# open (MYFILE, 'temp');
# printit(\*MYFILE);
# sub printit {
#     my $fh = shift;
#     while (<$fh>) {
#         print;
#     } 
# }
### pre-pass FH version
# sub get_next_non_comment_line{
# 	do {
# 		$_=<RDF>;
# 		$nline++;
# 		if ($verbose && /^#/) {
# 			printf "Ignored comment line $nline: $_";
# 		}
# 	} while (/^#/);
# }
### pass-FH version
sub get_next_non_comment_line {
    my $fh = shift;
    do {
        $_=<$fh>;
        $nline++;
        if ($verbose && /^\s*#/) {
            printf "Ignored comment line $nline: $_";
        }
    } while (/^\s*#/);
}

# this needs update of variables .. #BUG5# 
sub die_on_syntax_error {
    $input_fn = shift;
    die "\nERROR: syntax incorrect in $input_fn on line $nline:\n$_\ndie\n\n";
}

# read rundata info
sub read_rundata {
    $nline=0;
    # read header until out of comment lines
    get_next_non_comment_line(\*RDF);
    # read one line at the time in a loop; 
    # sub above has already loaded first non-comment line in pattern space $_
    do {
        # printf (ODF "%s",$_);
        chop();
        # $nline++;  # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        # next, extract fields per validity range
        
        # 1) start and end dates
        $_ =~
 /^(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})\s+(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})/
          || die_on_syntax_error($rundata_fn);
        $start_YY=$1;
        $start_MM=$2;
        $start_DD=$3;
        $start_hh=$4;
        $start_mm=$5;
        $end_YY=$6;
        $end_MM=$7;
        $end_DD=$8;
        $end_hh=$9;
        $end_mm=$10;
        print "rundata file: \n  start: $start_YY$start_MM$start_DD $start_hh:$start_mm\n"
            if ($verbose);
        print "  end  : $end_YY$end_MM$end_DD $end_hh:$end_mm\n" if ($verbose);
        
        # 2) parameters, one line for each
        # $_ = <RDF>;
        get_next_non_comment_line(\*RDF);
        chop();
        # $nline++;  # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$thres_gap\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($rundata_fn);
        $thres_gap_rd=$1;
        print "  thres_gap_rd = $thres_gap_rd\n" if ($verbose);
        
# #### ALL FOLLOWING CALCULATIONS MUST BE CHECKED #BUG7# ***done*** obsoleted 160417
# ## not obtain start and end dt in cdyr units                #BUG6# looms here
# $start_cdoy=&DoYR($start_DD,$start_MM,$start_YY);           # current day of the year
# $start_ddoy=$cdoy + (($start_mm/60.)+$start_hh)/24.;        # real time in units of doy
# $start_dy=&dysize($start_YY);                               # days in current year
# $start_dy_last=&dysize($start_YY_last);                     # days in "the year of the last
#                                                             #     (previous) data point"
# $start_cdyr=$start_YY+( (($start_mm/60.)+$start_hh)/24. + $start_cdoy )/$start_dy;  # Digital
#                         (real) year coordinate <==this is #BUG6# ***done*** obsoleted 160417
# # print "cdoy=$cdoy, dy=$dy, cdyr=$cdyr, cdyr_last=$cdyr_last\n";
# $end_cdoy=&DoYR($end_DD,$end_MM,$end_YY);                   # current day of the year
# $end_ddoy=$cdoy + (($end_mm/60.)+$end_hh)/24.;              # real time in units of doy
# $end_dy=&dysize($end_YY);                                   # days in current year
# $end_dy_last=&dysize($end_YY_last);                         # days in "the year of the
#                                                             #     last (previous) data point"
# $end_cdyr=$end_YY+( (($end_mm/60.)+$end_hh)/24. + $end_cdoy )/$end_dy;  # Digital (real)
#                                 year coordinate <==this is #BUG6# ***done*** obsoleted 160417
# # print "cdoy=$cdoy, dy=$dy, cdyr=$cdyr, cdyr_last=$cdyr_last\n";

        # replaced with epoch: 
        $dt_start    = DateTime->new(year => $start_YY, month => $start_MM, day => $start_DD,
                                     hour => $start_hh, minute => $start_mm);
        $start_epoch = $dt_start->epoch();
        $dt_end      = DateTime->new(year => $end_YY, month => $end_MM, day => $end_DD,
                                     hour => $end_hh, minute => $end_mm);
        $end_epoch   = $dt_end->epoch();
        # but remain human-conscious:
        $start_t = sprintf("%4d%02d%02d %02d%02d",
                          $start_YY,$start_MM,$start_DD,$start_hh,$start_mm);
        $end_t   = sprintf("%4d%02d%02d %02d%02d",
                          $end_YY,$end_MM,$end_DD,$end_hh,$end_mm);
        
                
        ## store in vectors that will be used inside the code
        # push(@rundata_start_t,      $start_cdyr);        
        # push(@rundata_end_t,        $end_cdyr);        
        push(@rundata_start_epoch,  $start_epoch);
        push(@rundata_end_epoch,    $end_epoch);
        push(@rundata_start_t,      $start_t);
        push(@rundata_end_t,        $end_t);
        push(@rundata_thres_gap,    $thres_gap_rd);

        # max flexibility with comment lines is causing some complexity
        # } while(get_next_non_comment_line(\*RDF));  # doesn't work
        # } while(<RDF>);
        get_next_non_comment_line(\*RDF);
    } while(eof(RDF) != 1);
}


# read database info
# the data base file format can be understood as the following combination of lines:
# - comments (as many as desired), and
# - sp_blocks (sp = sampling point, e.g. 'Amont'), themselves structured as:
#   - a label: a word describing the sp and terminated with a colon '<string>:', and
#   - one one many "numeric_sub-block's, consisting each of:
#     - a date range (which defines the start of a numeric sub-block), followed by
#     - one or many line(s), each one defining a single parameter "$par_name = value"
sub read_db {
    $nline=0;
    $found_sp_block=0;  # this is not used at the end: def'd to stop reading once done
                        # w/ this sp, but this was not implemented
    $in_sp_block=0;     # this one is crucial for logics
    # read header until out of comment lines
    get_next_non_comment_line(\*DBF);
    # read one line at the time in a loop; 
    # sub above has already loaded first non-comment line in pattern space $_
    ## OK now for another interesting twist: 
    # - with a do { } while(); loop, I get the error >Can't "next" outside a loop block<
    # - and http://www.perlmonks.org/?node_id=1005567 comes to the rescue:
    #   - essentially, do {} while is not considered a loop,
    #   - but using double curly braces will fix it - it did.
    # -> if this isn't a hack-feature !?
    do {{
        # printf (ODF "%s",$_);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        # next, extract fields per validity range
        
        ## the following logics is quite intricate. This is a consequence of the freedom
        ## to have as many numerical sub-blocks as desired; to have main "sampling-point"
        ## header lines appear in any order wrt other sampling points; free comments-for-all...
        # 0) Must first look if this is a new sampling point or a numeric sub-block
        ## THIS IS THE SUTIDEST I HAVE DONE IN A WHILE: 
        ## if ($_ =~ /^[0-9]/ || die_on_syntax_error($db_fn)) {
        if ($_ =~ /^[0-9]/) {
            print "db file: found numeric block header\n" if ($verbose);
            if($in_sp_block == 0){ # not in the right block though - skip
                print "         in_sp_block = $in_sp_block => SKIP upcoming num sub-block\n"
                   if ($verbose);
                skip_num_block();
                next;
            } else {
                print "         in_sp_block = $in_sp_block => PROCESS upcoming num sub-block\n"
                    if ($verbose);
                # do nothing .. will resume with processing of date fields
                # after this nesting of logics
            }
        } else { # non-numeric implies the start of a sp_block
            print "db file: found non-numeric, new sp block header\n" if ($verbose);
            # check if it is the desired sp block
            $_ =~ /^([^\W_]+):/ || die_on_syntax_error($db_fn);
            $db_SP=$1;
            print "         db_SP=>$db_SP< => " if ($verbose);
            if($db_SP ne $SP) {
                $in_sp_block=0;
                print "does not match SP=>$SP< -- skip to next sub-block\n" if ($verbose);
                # The 'skip' sub below will skip $n_db_params lines plus collect the one 
                # after the entire block (num or sp header). 
                # So, skipping the NUMERICAL header line (date range) that just follows
                # after the current line (SP) must be done with an extra call to 
                # 'get_next_non_comment..'
                get_next_non_comment_line(\*DBF);
                skip_num_block();
                next;
            } else { # else means proper SP has been found, proceed 
                print "does !!! match SP=>$SP< -- process following sub-block\n" if ($verbose);
                $found_sp_block=1;
                $in_sp_block=1;
                # simply find and load the next, upcoming NUMERICAL header line
                get_next_non_comment_line(\*DBF);
                # then will resume with processing of date fields
            }    
        }
                
        # this is one sp_ or num_block we want to load
        # 1) start and end dates
        # get_next_non_comment_line(\*DBF);
        # chop();
        # $nline++;   # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~
 /^(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})\s+(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})/
          || die_on_syntax_error($db_fn);
        $start_YY=$1;
        $start_MM=$2;
        $start_DD=$3;
        $start_hh=$4;
        $start_mm=$5;
        $end_YY=$6;
        $end_MM=$7;
        $end_DD=$8;
        $end_hh=$9;
        $end_mm=$10;
        print "db file: \n  start: $start_YY$start_MM$start_DD $start_hh:$start_mm\n"
            if ($verbose);
        print "  end  : $end_YY$end_MM$end_DD $end_hh:$end_mm\n"
            if ($verbose);
        
        # 2) parameters, one line for each
        # $_ = <DBF>;
        ## RETIRED 160417 ## get_next_non_comment_line(\*DBF);
        # chop();
        # $nline++;   # increment is done in get_next_non_comment_line()
        # print ">$_<\n" if ($verbose);
        # $_ =~ /^\s+\$n_spate_thres_up\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        # $n_spate_thres_up_db=$1;
        # print "  n_spate_thres_up_db = $n_spate_thres_up_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_recent_to_consider\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_recent_to_consider_db=$1;
        print "  n_recent_to_consider_db = $n_recent_to_consider_db\n" if ($verbose);

        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_slope_up_above_thres\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_slope_up_above_thres_db=$1;
        print "  n_slope_up_above_thres_db = $n_slope_up_above_thres_db\n" if ($verbose);

        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$spate_thres_up\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $spate_thres_up_db=$1;
        print "  spate_thres_up_db = $spate_thres_up_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_not_in_spate_req\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_not_in_spate_req_db=$1;
        print "  n_not_in_spate_req_db = $n_not_in_spate_req_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$dq_local_min\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $dq_local_min_db=$1;
        print "  dq_local_min_db = $dq_local_min_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_thres_up\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_thres_up_db=$1;
        print "  n_thres_up_db = $n_thres_up_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$thres_up\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $thres_up_db=$1;
        print "  thres_up_db = $thres_up_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_thres_dn\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_thres_dn_db=$1;
        print "  n_thres_dn_db = $n_thres_dn_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        # $nline++;     # increment is done in get_next_non_comment_line()
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$thres_dn\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $thres_dn_db=$1;
        print "  thres_dn_db = $thres_dn_db\n" if ($verbose);
        
        # #### erased block similar to above, re. #BUG7# ***done*** obsoleted 160417
                
        # replaced with epoch: 
        $dt_start    = DateTime->new(year => $start_YY, month => $start_MM, day => $start_DD,
                                     hour => $start_hh, minute => $start_mm);
        $start_epoch = $dt_start->epoch();
        $dt_end      = DateTime->new(year => $end_YY, month => $end_MM, day => $end_DD,
                                     hour => $end_hh, minute => $end_mm);
        $end_epoch   = $dt_end->epoch();
        # but remain human-conscious:
        $start_t = sprintf("%4d%02d%02d %02d%02d",
                           $start_YY,$start_MM,$start_DD,$start_hh,$start_mm);
        $end_t   = sprintf("%4d%02d%02d %02d%02d",
                           $end_YY,$end_MM,$end_DD,$end_hh,$end_mm);
        

        ## store in vectors that will be used inside the code
        # push(@db_start_t,                  $start_cdyr);        
        # push(@db_end_t,                    $end_cdyr);        
        push(@db_start_epoch,              $start_epoch);
        push(@db_end_epoch,                $end_epoch);
        push(@db_start_t,                  $start_t);
        push(@db_end_t,                    $end_t);
        ## RETIRED 160417 ## push(@db_n_spate_thres_up,     $n_spate_thres_up_db);        
        push(@db_n_recent_to_consider,     $n_recent_to_consider_db);
        push(@db_n_slope_up_above_thres,   $n_slope_up_above_thres_db);
        push(@db_spate_thres_up,           $spate_thres_up_db);        
        push(@db_n_not_in_spate_req,       $n_not_in_spate_req_db);        
        push(@db_dq_local_min,             $dq_local_min_db);        
        push(@db_n_thres_up,               $n_thres_up_db);        
        push(@db_thres_up,                 $thres_up_db);        
        push(@db_n_thres_dn,               $n_thres_dn_db);        
        push(@db_thres_dn,                 $thres_dn_db);        

        # max flexibility with comment lines is causing some complexity
        # } while(get_next_non_comment_line(\*DBF));  # doesn't work
        # } while(<DBF>);
        get_next_non_comment_line(\*DBF);
    }} while(eof(DBF) != 1);
}

# this is when at a date range line, and knowing the entire numerical block can be skipped
# this is invoked after having determined that current ine is start of 'numeric' bloc, i.e.
# the number of non-comment lines to skip is simply the number of parameters.
# So, invoke get_next_non_comment_line $n_db_params times
sub skip_num_block {
    for($j=0;$j<$n_db_params;$j++){
        get_next_non_comment_line(\*DBF);
        # and do nothing about it = skip
    }
    # but need one more invocation to get the next block header line
    get_next_non_comment_line(\*DBF);
}
