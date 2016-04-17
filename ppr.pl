#!/usr/bin/perl

# file name  : ppr.pl - Poulpette's Peak Recognizor - branched off 160415 from cl2dat.pl
# author     : initial J. Farine for Milandre Turb+Q data.
#              core developper C. Vuilleumier after 160415
#              Note: throughout the code, the comments [ NSF = "blah" ] stand for "Note For Self" and apply to JF
# purpose    : peak search
#              Gaps in the data properly detected and accounted for (to avoid false Delta-values)
#               - gaps are flagged when the time difference between successive points is larger 
#                 than the programmed probe sampling time, actually larger than the parameter $thres_gap.
#                 $thres_gap is read from the 'rundata_<sampling point>.txt' file
#              The fine tuning parameters for the peak search are stored in the files 'ppr_db_Q.txt' and 'ppr_db_T.txt' 
#              - see description below
# usage      : ppr.pl rfn [ploc]
#              where:
#              - rfn is the root file name used to build other filenames for this data, which are:
#                <rfn>.tod is the file with reformatted CaveLink data (latest point in file is latest in time)
#                <rfn>.tmp is a temp file that will be erased, or should have been :-)
#                <rfn>.csv is the data file suitable for "analysis" with Excel
#                <rfn>.dat is the data file suitable for analysis with PAW
#              - ploc is the probe location [tmp for DB dev - not sure this is actually necessary ! see DB discussion below]
#              -> see FILE NAME CONVENTION below ! The syntax of 'rfn' must contain the 'sampling point' and the data type or 'Observable' (Q or T)
# output fmt : Many ! see the code. Some outpit files get a legend printed on top. Some don't, in order to prevent
#              crashes from the program that reads them (PAW, ROOT,..)
#              [NFS: the two lines below are likely obsolete]
#              Excel .csv: "%02d/%02d/%4d %02d:%02d, %+8.4f, %15.10f, %5.1f, %7.3f, %+9.5f, %+9.5f\n" 
#              Data .dat and .spt: see code ! (both are read by ReadMoti.C as per 140227)
# description: - reads <time> <value> in input data file <rfn>.tod and searches for peaks
#              - the script now (160415) also allows input of the probe location ploc for future use with DB (perhaps, see below)
#                Mechanism as per 160415:
#                - while the script reads a second command line argument [ploc], it is likely already obsolete:
#  !!>>          - FILE NAME CONVENTIONS !!!
#                  the input data file should be named <Observable>_<Sampling point>_<whatever>.tod where:
#                  - Observable is e.g. 'Q' or 'T' (variable name is $Obs)
#                  - Sampling Point is e.g. 'Amont', 'Gal80', 'Bure', 'Saivu' for T (or 'Saivu+Bame' for Q) (variable name is $SP)
#                  - whatever is free, but should not include '_' not '.'
#                  THE VALUES OF $Obs AND $SP ARE NOT HARD-CODED ANYWHERE !! By design ! Read on:
#                  -> example: the input file 'Q_Amont_2003.tod'
#                              implies $Obs="Q" and $SP="Amont"
#                              therefore the script will look for the rundata file named 'rundata_Amont.text'
#                              and for the DB file 'ppr_db_Q.txt' .. in which it will look for the 'Amont' data block
#                  -> other example: input file 'San_Gli_Er.tod' => 'rundata_Gli.txt' and block named 'Gli' in DB file 'ppr_db_San.txt'
#              - the rate of change of level is produced in two units: m/h and cm/min [NFS: get rid of redundance in ppr.pl]
#                IMPORTANT this rate is calculated **from the current to the next** pt,
#                          but because the data goes backward in time, the slope listed at one
#                          data point (time) is the slope ***to get to** this data point.
#                [NFS: the above was true in the initial script, where reformatting was done here. Not sure if it still applies,
#                now that the reformatting was moved to the dedicated script cl_refmt.pl]
# definitions: - a _peak_ is a point in time where the quantity of interest (water level) reaches a local maximum
#              - a _through_ (or valley) is " " " " " " " " .. local minimum [associated variables are also called "_base"]
#              - a _spate_ (or spate event, or flood, or high water event, crue en F) is the period of time between two **throughs**
#                (note: not between a peak and the next through)
#              - ddoy means "digital day of the year" .. a bit of a misnomer: digital means a single scalar instead of a list of integers:
#                ddoy is the time (of anything) converted from MM/DD/YY hh:mm:ss:cc to a real number. 
#                Conventions for this conversion vary, i.e. where 1 unit is either a year or a day; the unit for ddoy is a day. 
#                So a std year starts at 0.00 (for Jan 1st 00:00) and ends at 365.00 (Dec 31st 24:00) [ a leap year 366.00 ]
#                See subroutines DoYR and dysize [NFS: check what happens after 365 ..]
#
# Versions:
# --- the following is left for background until 160415 --- may be obsolete ---
# 130421 - debugged txt version and downloaded data to play (49k requested)
#        - inverted DD and MM assignments, they were american! But checking again looked
#          right to do so as just above, I invert them so Excel has MM/DD/YYYY... TBC
# 140217 - Mavericks broke Perl .. comment out "require ctime.pl" and "use Switch"
# 140223 - added threshold detector for dh/dt, implemented code to detect 
#          (crue = rise, spate) - define spate if current and last n_thres dh/dt are > $spate_thres_up
#        - a bit tricky given the data goes backwards (better: reordered file for off-line)
#        - also gives base / max levels for that spate
#        - saves spates in new file .spt - see code for format
#        - playing around with 'basic.dat' file to re-learn ROOT,
#          see macro hist1.cxx in moti/data/2014
# 140226 - added ttns_d time to next spate (days) (which was seen last since data is backwards)
#        - started serious ROOT macro - can now plot lvl, dh/dt and new_spate together
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
# 160416 - finished implementation of db mechanism, and tested ok
#          NOTE: IF EDITING THE LIST OF PARAMETERS, look for the following comment line throughout the script:
#          ### edit the above if changing/adding/removing the db parameters
# 160417 - lame attempt to port to github
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
#          (Q: is that slope always the same at the same levels ?? - need data)
# 140302 - see notes above under same dates
#        - check new peak calculations, esp. throughs - dates to <peak> can be odd
#        - check 3/4 algo, improve, implement to peaks/throughs too
# 140304 - Trigger:
#          - replace last_but1|2 with test on n_not_in_spate >= n_not_in_spate_req & check still OK
#          + still missing b7 (requires now arrays of size 5, not 4.. re-include dh_local_vals then)
#          + still triggering on fake b10b
#          + fluke ns#1 2011.0428652968
#          + flukes from fluctuations during single, nice broad event
#          + look at all data from start and  polish algo
#          + revisit bump-finding ! e.g. 0.11
#          -> check out http://search.cpan.org/~randerson/Statistics-LineFit-0.07/lib/Statistics/LineFit.pm
#        + Peak/trough calculations
#          - check
#          - sp. after 2011.908 - next Pk is from before!!
# 150907 - for DAN really:
#          - determine if the first and second 1/2h IVL can predict the overall magnitude of the spate (see 20110901 16:30)
# 160414 - debug needed: look for #BUG<n>#, n=1,2,3,..
#        + cleanup doc: look for [NFS .. ]
# ------- created ppr.pl from cl2dat.pl ----------------------------------------------------
# 160415 - debugging needed as per above
#        + also debug argument passing to subs (now two mechanisms !!)
#        + get rid of anything talking about level, centi/meters etc.. this should be generic value/unit ( either Turb or Q)
#        + similarly, make clear that Sampling Time ST is always specified in MINUTES
#        + [ NSF: refresh my memory on how thresholds & criteria work. For one: what does $gap_max wrt $thres_gap ? ]
#        + DATABASE PRELIMINARY IDEAS -- no decisions made yet !!! 
#          need to implement a database mechanism to do 1) and 2) below
#          1) load peak search parameters from external data files,
#             named e.g. ppr_db_T.txt and ppr_db_Q.txt (Turbidity and discharge "probes" are different),
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
#        + 2) implement similar idea for describing the input data to the script, with external files
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
#        + Implementation ideas:
#          - script is invoked from master script with two arguments: rfn and ploc
#            - rfn points to the input data file and creates all output files with samme root file name
#            - rfn contains a "waveform" <time> <value>; gaps are allowed (periods without data),
#              else data is assumed at regular sampling time intervals ST
#            - the script looks for peaks (and other structural parameters) in the data
#            - to do that effectively, the script needs to know of:
#              1) parameters to optimize the peak search as data quality may vary within
#                 the waverform (achieved with DB files ppr_db_[T|Q].txt)
#              and also of:
#              2) the data format, like the current ST (achieved with DB files rundata_<location>.txt)
#            - for this the script needs to know a) if it is looking at Turb or Q and b) the probe location
#            - it will then figure out which parameters to use as time goes by directly from the database
#              [NFS: careful with boundaries of time ranges !! best if they fall in periods with probe off ? ]
#            => it is not obvious to me that ploc needs to be specified on the command line ! 
#               a cleaner mechanism would be to craft rfn to include ploc, i.e. $rfn="Q_<ploc>_other.dat"
#               i.e. a disciplined, fixed format rfn will allow the script to find its pointers to the DB
#               (e.g. in the example above from Cécile, rfn already contains either T or Q !)
#        -> running out of steam at the end of 160415 .. rundata implements, but not db yet
# 160416 - evaluate if the amplitude of the <observable> (level) should be taken into account too in the 
#          spate detector. It was not the case in Môtiers, but for probes with a long ST, like >= 1h, it might
#          be relevant and increase the sensitivity to small spates.
#        => TBD later if of interest and worth the time - by core developper :-)
#
# Careful, this is the end of the list of TODOes, not Versions !!
# add new TODOes above 'Careful', and new Versions above 'TODOes' :-)

### start by formally requiring all external perl packages needed by this script
### (for Python users this is the "import" block of the script)
# require "ctime.pl";
use     Sys::Hostname;
# not sure why I commented following line out ..
# use 	Switch;
# but 'use  feature switch' is available since perl 5.10.1 according to http://perldoc.perl.org/perlsyn.html#Switch-Statements
use		  Math::Trig;
# these added 160415 JF to pass file handles to a subroutine.. 
# .. well, the example I found 'used' these two, so I just stupidly copy them here, not sure they are needed.
# Getting errors, I commented them out and my copy-pasted snippet just works FINE.
# use     strict;       # should read http://perldoc.perl.org/strict.html
# use     warnings;     # should read http://perldoc.perl.org/warnings.html


### CUSTOMIZABLE PARAMETERS +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
#
# Note: in an upcoming update, pars in categories custo2+3 will be read from an external
#       text file, the "database". Definitions will always remain here, just that they
#       might get overwritten

# custo 1 - this is to alter how the program behaves in general
$verbose = 1;	# set to 1 for debugging

# custo 2 - this is to inform the program about the data it is being given
$path_rundata       =    ".";   # tell script where to find DB rundata_<location>.txt files
#                               # script will then look for sample location $SP in $rfn to
#                               # construct full rundata file name
# gap detector - will look for gaps in data by flagging intervals between points > $thres_gap 
# (this is about finding out when data is missing)
$thres_gap          =     31;   # time in minutes

# custo 3 - this is to fine tune the peak search
$path_db            =    ".";   # tell script where to find DB ppr_db_[Q|T].txt files
## number of intervals to include in avdhdt  (#BUG2#? this is used nowhere in the code ?!?)
$n_avdhdt=6;
## requirements to define spate (up) or peak (down) conditions
# Note the different uses  to avoid false positive triggers !!
$n_spate_thres_up   =      4;   # number of consecutive data points that must be above threshold
#new# $n_recent_to_consider   =      4;   # number of consecutive data points that must be looked at for being above threshold or not
#new# $n_slope_up_above_thres   =      3;   # number of data points in the $n_recent_to_consider  most recent that must be above threshold
$spate_thres_up     =      0;   # threshold value [cm/min] (must experiment with data) 
$n_not_in_spate_req =      3;   # request that these many pts are "not in spate" prior to allowing a new spate (#BUG3#? - formerly said not not in spate)
$dh_local_min       =      3;   # min raise requested (in mm) between [0] and [3]
## the following is for peak/through detection
# peak/through detector have a slightly different logics
# careful with confusion up/down here: read <whatever> "for ending going _up/_dn after passing the point"
$n_thres_up         =      4;   # number of consecutive data points that must slope *down* before the one going up
$thres_up           =      0;   # threshold value [m/hour] (must experiment with data)
$n_thres_dn         =      4;   # number of consecutive data points that must slope *up* before the one going down
$thres_dn           =      0;   # threshold value [m/hour] (must experiment with data)
### edit the above if changing/adding/removing the db parameters
# IF UDATING NUMBER OF DB PARAMETERS THE FOLLOWING MUST BE UPDATED TOO 
$n_db_params        =      8;   # number of parameters in database
### edit the above if changing/adding/removing the db parameters
### END OF CUSTOMIZABLE PARAMETERS +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-

# consistency checks on the above
if ($thres_up < $thres_dn){
	  die("Error: thres_up=%f < thres_dn=%f (they can be equal)\ndie\n",$thres_up < $thres_dn); 
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
# - 'par_<blah>' : variables that are read form the <blah> file (blah= 'rundata' or 'db') - these are scalars (one value)
# - '<blah>_par' : variables used in memory in this script to be checked against as script progresses - these are vectors (>=1 value/s)
### extract from rfn the fields necessary to build the appropriate rundata/DB file names
# $rfn =~ /^(\w)_([^\W_]+)_[^\.]+\.tod/;      # doesn't work
# $rfn =~ /^([^\W_])_([^\W_]+)_[^\.]+\.tod/;  # doesn't work
$rfn =~ /^([^\W_])_([^\W_]+)_/ || die "\nERROR: syntax incorrect in $rfn:\ndie\n\n";;
$Obs=$1;    # Observable : e.g. 'Q' or 'T' (but this is hard-coded nowhere, so it could be nay character !)
$SP=$2;     # Sampling Point: e.g. 'Amont', 'Gal80', 'Bure', 'Saivu' for T (or 'Saivu+Bame' for Q)
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
print "rundata_start_t      = @rundata_start_t\n" if ($verbose);        
print "rundata_end_t        = @rundata_end_t\n" if ($verbose);        
print "rundata_thres_gap    = @rundata_thres_gap\n" if ($verbose);        
### check consistency of rundata time ranges
for ($i=0;$i<=$#rundata_start_t;$i++){
    # check 1: start(i) must be < end(i)
    if($rundata_start_t[$i] >= $rundata_end_t[$i]){
        die("ERROR in rundata file $rundata_fn:\nstart time $rundata_start_t[$i] >= end time $rundata_end_t[$i]\n");
    }
    # check 2: end(i) must be < start(i+1)
    if($i < $#rundata_start_t){
        if($rundata_end_t[$i] >= $rundata_start_t[$i+1]){
            die("ERROR in rundata file $rundata_fn:\nend time $rundata_end_t[$i] >= start time $rundata_start_t[$i+1]\n");
        }
    }
}
print "No time inconsistencies found in rundata file $rundata_fn of interest to sampling point $SP\n\n";


### database: open, load and close DB file
open(DBF,"$db_fn")    || die "Can't open  input file: $db_fn, $!\n"; 
print "\nsucessfully opened db file $db_fn\n" if ($verbose);
read_db();
close(DBF); 
print "db_start_t              = @db_start_t\n" if ($verbose);
print "db_end_t                = @db_end_t\n" if ($verbose);
print "db_n_spate_thres_up     = @db_n_spate_thres_up\n" if ($verbose);
print "db_spate_thres_up       = @db_spate_thres_up\n" if ($verbose);
print "db_n_not_in_spate_req   = @db_n_not_in_spate_req\n" if ($verbose);
print "db_dh_local_min         = @db_dh_local_min\n" if ($verbose);
print "db_n_thres_up           = @db_n_thres_up\n" if ($verbose);
print "db_thres_up             = @db_thres_up\n" if ($verbose);
print "db_n_thres_dn           = @db_n_thres_dn\n" if ($verbose);
print "db_thres_dn             = @db_thres_dn\n" if ($verbose);
### edit the above if changing/adding/removing the db parameters

### check consistency of db time ranges
for ($i=0;$i<=$#db_start_t;$i++){
    # check 1: start(i) must be < end(i)
    if($db_start_t[$i] >= $db_end_t[$i]){
        die("ERROR in DB file $db_fn:\nstart time $db_start_t[$i] >= end time $db_end_t[$i]\n");
    }
    # check 2: end(i) must be < start(i+1)
    if($i < $#db_start_t){
        if($db_end_t[$i] >= $db_start_t[$i+1]){
            die("ERROR in DB file $db_fn:\nend time $db_end_t[$i] >= start time $db_start_t[$i+1]\n");
        }
    }
}
print "No time inconsistencies found in DB file $db_fn of interest to sampling point $SP and observable $Obs\n\n";

exit;

#### CREATE I/O FILE NAMES
# this was for debugging
# $fnam="motidata_20110729_0700.txt";
# $tnam="motidata_20110729_0700.tmp";
# $dnam="motidata_20110729_0700.dat"G
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

open(IDF,"$tnam")    || die "Can't open  input file: $tnam, $!\n";  
open(ODF,">$enam")   || die "Can't open output file: $enam, $!\n";  
open(ODDF,">$dnam")  || die "Can't open output file: $dnam, $!\n";  
open(ODSF,">$snam")  || die "Can't open output file: $snam, $!\n";  
open(ODSLF,">$slnam")|| die "Can't open output file: $slnam, $!\n";  
open(ODGF,">$gnam")  || die "Can't open output file: $gnam, $!\n";  
open(OSF,">$sumnam") || die "Can't open output file: $sumnam, $!\n";  
# open(ODTF,">$testnam") || die "Can't open output file: $testnam, $!\n";  

# print out some headers
printf (ODGF "threshold for detection of gaps = %d min\n",$thres_gap);

printf (ODSF "Legend:\nnspat tsls_d  _____cdyr______ __hT(m)_  \n--- End of Legend ---\n");

printf (ODSLF "Legend:\nns\# nspat (pt _____ID): YYYY MM DD hh mm  tsls_d  _____cdyr______ __hT(m)_  ");
printf (ODSLF "pk: _____cdyr______ hTmax(m)  _dhT(m)  _Dddoy");
printf (ODSLF "\n                                                                            ");
printf (ODSLF "tr: _____cdyr______ hTmin(m)  _dhT(m)  ddoy_at_min\n--- End of Legend ---\n");

printf (ODDF "Legend:\nMM DD YYYY hh mm  __hT(m)_ _____cdyr______ __cdyr-YY0__ __ddoy_  ");
printf (ODDF " _dhdt_mph dhdt_cmpm");
printf (ODDF "  _DeltaSL_  From here on, a galore of 1/0 flags, in this order:\n");
printf (ODDF "up_met is_max  dn_met is_min  ");
printf (ODDF "  +7.1f: dh_local ");
printf (ODDF "  above_thres in_spate in_spate_last in_spate_last_but1 in_spate_last_but2");
printf (ODDF "  n_not_in_spate new_spate\n--- End of Legend ---\n");


#### PROCESS INPUT DATA FILE

### GLOBAL INITS (ok, a bit of a misnomer)
## Do **not** change those unless you know what you are doing
# scan for absolute extrema - start by setting impossible values
$lvl_abs_min        = +60;
$lvl_abs_max        = -20;
$lvl_abs_min_cdyr   =   0.;
$lvl_abs_max_cdyr   =   0.;
$lvl_abs_min_ymdhs  =   0;
$lvl_abs_max_ymdhs  =   0;
$dhdt_abs_min       = +20;
$dhdt_abs_max       = -20 ;
$dhdt_abs_min_cdyr  =   0.;
$dhdt_abs_max_cdyr  =   0.;
$dhdt_abs_min_ymdhs =   0;
$dhdt_abs_max_ymdhs =   0;
$dhdt_abs_min_lvl   = +60.;
$dhdt_abs_max_lvl   = -20.;


#### INITs for peak search -- this section has no parameters to modify. 
## Do **not** change those unless you know what you are doing
$cdyr_last=0;
$lvl_last=0;
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
$dh_max=0;
$new_spate=0;
$last_spate_ddoy=0;
$dhdt_mph_last=0;
$YY_last=0;
$is_max=9;
$is_min=9;
$theta=-9.99;

# bulk - a standard input line follows for reference (**after** substitution of '.' with '/')
# 7/29/2011 06:00, -1.8464

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
    $lvl=$6;
    # print "$YY$MM$DD $hh:$mm lvl=$lvl lvl_last=$lvl_last\n";
    
    # cdyr calculations                             # #BUG6# looms here
    $cdoy=&DoYR($DD,$MM,$YY);                       # current day of the year
    $ddoy=$cdoy + (($mm/60.)+$hh)/24.;              # real time in units of day of the year
	  $dy=&dysize($YY);                               # days in current year
	  $dy_last=&dysize($YY_last);                     # days in "the year of the last (previous) data point"
	  $cdyr=$YY+( (($mm/60.)+$hh)/24. + $cdoy )/$dy;  # Digital (real) year coordinate <==this is #BUG6#
    # print "cdoy=$cdoy, dy=$dy, cdyr=$cdyr, cdyr_last=$cdyr_last\n";

    $ndata++;
    
    if($ndata == 1){
    	  $YY0=$YY;
    }

	  # this is kind of a cheap "pause", asking the program to wait for input
	  # $blah=<STDIN>; 
	
  	# update abs extrema if applicable
	  if($lvl > $lvl_abs_max) {
        $lvl_abs_max = $lvl;
        $lvl_abs_max_cdyr = $cdyr;		
        $lvl_abs_max_ymdhs = sprintf("%02d%02d%02d %02d:%02d",$YY,$MM,$DD,$hh,$mm);		
	  }
        if($lvl < $lvl_abs_min) {
        $lvl_abs_min = $lvl;
        $lvl_abs_min_cdyr = $cdyr;
        $lvl_abs_min_ymdhs = sprintf("%02d%02d%02d %02d:%02d",$YY,$MM,$DD,$hh,$mm);		
	  }
	
	  # running min/max lvls
    if($ndata == 1) {
		    &setmax();
		    &setmin();
    } else {
        if($lvl > $lvl_max) {
			      &setmax();
        }
        if($lvl < $lvl_min) {
			      &setmin();
        }
    }

	  # yet another local variable, will store 5 (highest index 4)
	  push(@dh_local_vals, $lvl);  
	  
	  ### Obtain parameters form DB and rundata files (yes this is doe for every point - suboptimal)
	  ## rundata first
    # # for testing during commissionning: 
	  # print "\n crdyr=$cdyr;  thres_gap b4 = $thres_gap, ";
	  # check 1: $cdyr is within time extrema in file
	  if ($cdyr < $rundata_start_t[0] || $cdyr > $rundata_end_t[$#rundata_end_t]){
	      die("ERROR current time $cdyr out of scope of file $rundata_fn:\n");
	  }
	  $found=0;
	  for ($i=0;$i<=$#rundata_start_t;$i++){
        # check 2: is $cdyr in current interval ?
        if($rundata_start_t[$i] <= $cdyr && $cdcyr <= $rundata_end_t[$i]){
            $found=1;
            $thres_gap = $rundata_thres_gap[$i];
            # # for testing during commissionning: 
            # print " [found match in rd block $i ] ";
            # goto AFTER-RD-LOOP;
            ## this is a hack - to get out of the loop
            $i=$#rundata_start_t;
        }
    }
    # AFTER-RD-LOOP:  # this generates and error, and 'Learning Perl' tells me to never use 'goto' ..
    die("ERROR current time $cdyr fell through the cracks of file $rundata_fn:\n") if ($found == 0);
    # # for testing during commissionning: 
	  # print " aft = $thres_gap\n";
    # $blah=<STDIN>;

    # Rate of change calculations
    #     If not first point read, should write calculations from "previous"
    # point (which is more recent), before writing data from CaveLink from current
    # IMPORTANT: read note in Description in top: the data goes backwards in time
    # and the consequence is that the calculation done apparently "forward" ends
    # showing the rate of change in the interval **leading to** that point. Also
    # the signs are not corrected because both negatives cancel out.
    if($ndata > 1){
        # calc rates
        $dh_m=($lvl-$lvl_last);
        $dh_cm=100*($lvl-$lvl_last);
        # corrected to the proper formula: the number of days in the years of the previous
        # data point is what matters
		    $dt_d=$dy_last*($cdyr-$cdyr_last);
        $dt_h=$dt_d*24;
        $dt_min=$dt_h*60;
        # print "cdyr_last=$cdyr_last cdyr=$cdyr, dt_min=$dt_min\n";
        # $answ = <STDIN>;
        if($dt_min == 0) {
            $dhdt_cpd=0;
            $dhdt_mph=0;
            $dhdt_cpm=0;
        } else{
            $dhdt_cpd=$dh_cm/$dt_d;
            $dhdt_mph=$dh_m/$dt_h;
            $dhdt_cpm=$dh_cm/$dt_min;
        }
    	  # use deltas above to check for gap
    	  if($dt_min > $thres_gap){	
    		    # there is a gap
    		    printf (STDOUT "--> data missing before %4d/%02d/%02d %02d:%02d for %8.0f min, %7.2f days (threshold=%d min)\n",
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
            # NEW 150907 - only do so if dt_min < $thres_gap, i.e. do not report extrema calculated over gaps !
            if($dhdt_mph > $dhdt_abs_max) {
                $dhdt_abs_max = $dhdt_mph;
                $dhdt_abs_max_cdyr = $cdyr;
                $dhdt_abs_max_lvl = $lvl;	
                $dhdt_abs_max_ymdhs	= sprintf("%02d%02d%02d %02d:%02d",$YY,$MM,$DD,$hh,$mm);
            }
            if($dhdt_mph < $dhdt_abs_min) {
                $dhdt_abs_min = $dhdt_mph;
                $dhdt_abs_min_cdyr = $cdyr;		
                $dhdt_abs_min_lvl = $lvl;
                $dhdt_abs_min_ymdhs	= sprintf("%02d%02d%02d %02d:%02d",$YY,$MM,$DD,$hh,$mm);
            }
        } # end of checks if there is a gap or not
    	  # check for data overlap
    	  if($dt_min < 0){
            printf (STDOUT "\n\n--> negative time interval to %4d/%02d/%02d %02d:%02d for %8.0f min, %7.2f days -- CHECK FOR DATA OVERLAP!\n",
                            $YY,$MM,$DD,$hh,$mm,$dt_min,$dt_d,$thres_gap);
            printf (ODGF "\n\nnegative time interval to %4d/%02d/%02d %02d:%02d for %8.0f min, %7.2f days -- CHECK FOR DATA OVERLAP!\n",
                          $YY,$MM,$DD,$hh,$mm,$dt_min,$dt_d,$thres_gap);
            $novlap++;
        }
        # for spate detector - define status of current slope CPM
        if($dhdt_cpm > $spate_thres_up) {
            $above_thres = 1;
            # do not that now, must use $n_above_thres for previous pt, i.e. *before* updating it
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
        push(@last_lvl_vals, $lvl);
        push(@last_cdyr_vals, $cdyr);
        push(@last_ddoy_vals, $ddoy);
        # try something different
        push(@ttm,$cdyr);
        push(@ll,$lvl);
                
        # for peak detector - define status of current slope MPH
        if($dhdt_mph > $thres_up) {
            $up_met = 1;
        } else {
            $up_met = 0;
        }
        # for peak detector - accumulate slope in array
        push(@last_slopeup_vals, $up_met);
        print "  -- max idx in last_slopeup_vals = $#last_slopeup_vals -- @last_slopeup_vals\n" if ($verbose);

        # for through detector - define status of current slope MPH
        if($dhdt_mph <= $thres_dn) {
            $dn_met = 1;
        } else {
            $dn_met = 0;
        }
        # for through detector - accumulate slope in array
        push(@last_slopedn_vals, $dn_met);
        print "  -- min idx in last_slopedn_vals = $#last_slopedn_vals -- @last_slopedn_vals\n" if ($verbose);
        
        # for spate detector: this test ensures that at least as many data points already 
        # have been read, as is required by $n_spate_thres_up
        if($ndata > $n_spate_thres_up) {
            # First algo tested
            # following check only returns 1 if **all** elements in last_thres_vals 
            # are 1 (above threshold), including the current one just read. Thus it
            # will trigger on the first point that makes $n_thres_sup consecutive above threshold
            # $in_spate=1;
            # for($i=0;$i<$n_spate_thres_up;$i++){
            #	    $in_spate *= $last_thres_vals[$i];
            # }
            ## try algo "3 out of 4" - assuming n_spate_thres is already 4
            $sum=0;
            for($i=0;$i<$n_spate_thres_up;$i++){
                $sum += $last_thres_vals[$i];
            }
            # get local change of level **in mm* - need current + previous 4 (not 3) points
            # Note! I don't understand the '+2' (and why not just '+1') - this is *bad*
            if($ndata > $nspate_thres_up+3){
                $dh_local = 1000.*($dh_local_vals[$n_spate_thres_up]-$dh_local_vals[0]);
            }
            # print "highest index in dh_local_vals = $#dh_local_vals\n"; # says 3 when $n_spate_thres_up=4
            # i.e. 3 is the highest for a total of 4 elements (as expected)
            # added 140304 requirement that 1st and last are 1
            # this is to avoid triggering on "zeroes-1-1-1-zeroes"
            if($sum >= 3 && $last_thres_vals[0] == 1 
                         && $last_thres_vals[$n_spate_thres_up-1] == 1
                         && $dh_local >= $dh_local_min){
                $in_spate=1;
            } else {
                $in_spate=0;
            }
            ##### check if new spate ###  remember data now goes *forward* in time
            if($in_spate && !$in_spate_last 
                         && !$in_spate_last_but1 
                         && !$in_spate_last_but2){
                         # && $n_not_above_thres >= $n_not_above_thres_req) {
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
            # if new_spate, conclude scanning for lvl_max and start new scan
            # (means peak must have been passed, restart!)
            # CONT HERE
            if($new_spate){
                # $lvl_delta = $lvl_max - $lvl;
                # $ddoy_delta = $ddoy_max - $ddoy;
                # if($ddoy_delta < 0) {
                #     $ddoy_delta += &dysize($YY-1);
                # }
                # set references for ***start of spate** (using "at last min" was *wrong*)
                $lvl_base=$last_lvl_vals[0];
                $ddoy_base=$last_ddoy_vals[0];
                if($nspate == 1){
                    $tsls_d=0;
                    $tsls_d_max=0;
                } else {
                    $tsls_d=$ddoy_base-$last_spate_ddoy;
                    if($tsls_d < 0) {
                        $tsls_d += &dysize($YY-1);
                    }
                    if($tsls_d > $tsls_d_max) {
                        $tsls_d_max = $tsls_d;
                    }
                }
                # output in two steps: 1 (here) - the start of the spate (next, 2: when peak found_)
                if($nspate > 1){
                    printf (STDOUT "\n");
                    printf (ODSF   "\n");
                    printf (ODSLF  "\n");
                } 
                # 160414 moved output of headers (legends) to top of files at user's request
                # 	else {
                # 		printf (ODSF "Legend:\nnspat tsls_d  _____cdyr______ __hT(m)_  \n--- End of Legend ---\n");
                # 		printf (ODSLF "Legend:\nns\# nspat (pt _____ID): YYYY MM DD hh mm  tsls_d  _____cdyr______ __hT(m)_  ");
                # 		printf (ODSLF "pk: _____cdyr______ hTmax(m)  _dhT(m)  _Dddoy");
                # 		printf (ODSLF "\n                                                                            ");
                # 		printf (ODSLF "tr: _____cdyr______ hTmin(m)  _dhT(m)  ddoy_at_min\n--- End of Legend ---\n");
                # 		printf (ODDF "Legend:\nMM DD YYYY hh mm  __hT(m)_ _____cdyr______ __cdyr-YY0__ __ddoy_  ");
                # 		printf (ODDF " _dhdt_mph dhdt_cmpm");
                # 		printf (ODDF "  _DeltaSL_  For here on a galore of 1/0 flags, in this order:\n");
                # 		printf (ODDF "up_met is_max  dn_met is_min  ");
                # 		printf (ODDF "  +7.1f: dh_local ");
                # 		printf (ODDF "  above_thres in_spate in_spate_last in_spate_last_but1 in_spate_last_but2");
                # 		printf (ODDF "  n_not_in_spate new_spate\n--- End of Legend ---\n");
                # 	}
                printf (STDOUT "New spate \# %5d (pt %7d) on %4d%02d%02d %02d%02d (after %6.3f days) h=%+7.3fm ",
                                $nspate,$ndata,
                                $last_YY_vals[0],$last_MM_vals[0],$last_DD_vals[0],$last_hh_vals[0],$last_mm_vals[0],
                                $tsls_d, $last_lvl_vals[0]);
                printf (ODSF "%5d %6.3f  %15.10f %+8.4f  ",
                              $nspate,
                              $tsls_d, $last_cdyr_vals[0],$last_lvl_vals[0]);
                              # printf (ODSF "Legend:\nnspat tsls_d  _____cdyr______ __hT(m)_  \n");
                printf (ODSLF "ns\# %5d (pt %7d): %4d %02d %02d %02d %02d  %6.3f  %15.10f %+8.4f  ",
                              $nspate,$ndata,
                              $last_YY_vals[0],$last_MM_vals[0],$last_DD_vals[0],$last_hh_vals[0],$last_mm_vals[0],
                              $tsls_d, $last_cdyr_vals[0],$last_lvl_vals[0]);
                # printf (ODSFL "Legend:\nnspat (pt _____ID): YYYY MM DD hh mm  tsls_d  _____cdyr______ __hT(m)_  ");
                # printf (ODTF "%+8.4f\n",
                # 	$lvl_delta);
                # *do not* reset min to current value, so as to scan for new max from the min -- this was wrong
                # 140305: why?
                # &setmax();
                $last_spate_ddoy=$ddoy_base;
            } # if newspate
            # safer now to clean arrays at the bottom
            shift(@last_thres_vals);
            shift(@last_YY_vals);
            shift(@last_MM_vals);
            shift(@last_DD_vals);
            shift(@last_hh_vals);
            shift(@last_mm_vals);
            shift(@last_lvl_vals);
            shift(@last_cdyr_vals);
            shift(@last_ddoy_vals);
            # Note! I don't understand the '+2' (and why not just '+1') - this is *bad*
            # if($ndata > $nspate_thres_up+5){
        		shift(@dh_local_vals);
            # }
        } # if ndata > n_spate_thres_up
        
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
            # printf (STDOUT "ndata=%6d  dx1=%.3f dx2=%.3f   dy1=%.4f dy2=%.4f  sl1=%9.2e sl2=%9.2e  DSL=%9.2e\n",
            #                 $ndata,$dx1,$dx2,$dy1,$dy2,$sl1,$sl2,$DSL);
            ## third try - average slopes.. -- not any better ! leave it in for now
            $ASL1=0;
            $ASL2=0;
            for($i=0;$i<7;$i++){
                $dxi=365*($ttm[$i+1]-$ttm[$i]);
                $dyi=$ll[$i+1]-$ll[$i];
                die("Error at ndata=$ndata crdy=$cdyr: dxi=0 for i=$i\ndie\n") if ($dxi == 0);
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
            # for peak scanning - trigger on slope change from ($n_thres_up consecutive +) to (-) after a minimum
			
            # following check only returns 1 if **all but the last** elements in last_slopeup_vals are 1 (cond met)
            $peak_cond_met=1;
            # important: do *not* use current point ! we want it have a neg slope so peak is hard-coded  @ last point ..
            # yes, yes, yes.. # array elements increased in test above, hence no '-1' below (and line above still holds)
            for($i=0;$i<$n_thres_up;$i++){
                $peak_cond_met *= $last_slopeup_vals[$i];
            }
            # then clean array at the bottom
            shift(@last_slopeup_vals);
            printf (STDOUT " ndata=%5d  lvl=%+7.4f  dhdt_mph=%+8.4f  peak_cond_met=%1d nspate=%1d  -- peak conds: ",
                            $ndata,$lvl,$dhdt_mph,$peak_cond_met,$nspate)  if ($verbose);
            if($dhdt_mph <= $thres_up && $peak_cond_met == 1 
                                      && $nspate > 0){
                printf (STDOUT " passed ++++++") if ($verbose);
                $is_max=1;
                $lvl_delta = $lvl_max - $lvl_base;
                if($lvl_delta > $dh_max){
                    $dh_max = $lvl_delta;
                }
                $ddoy_delta = $ddoy_max - $ddoy_base;
                if($ddoy_delta < 0) {
                    $ddoy_delta += &dysize($YY-1);
                }
                # now that peak was found, can close up entry on new spate
                    # output in two steps: 1 (above) - the start of the spate; 2 (here): when peak found
                printf (STDOUT " to %+7.3fm on %4d%02d%02d %02d%02d (dh=%6.3fm over %6.3f days)",
                  $lvl_max,$YY_max,$MM_max,$DD_max,$hh_max,$mm_max,$lvl_delta,$ddoy_delta);
                # reset min to here, so as to look for next min down from the peak
                if($peak_passed == 1){
                    printf (STDOUT "\n                                                                            ");
                    printf (ODSLF "\n                                                                            ");
                    # printf (ODSLF "\n                                                                            ");
                }
                # 141021: comment for now ("0,>1 nspates" problem)
                # printf (ODSF "%15.10f %+8.4f  %+7.3f  %6.3f  ",
                # 	$cdyr_max,$lvl_max, $lvl_delta,$ddoy_delta);
                printf (ODSLF "pk: %15.10f %+8.4f  %+7.3f  %6.3f",
                               $cdyr_max,$lvl_max, $lvl_delta,$ddoy_delta);
                $peak_passed=1;
                # printf (ODSFL "pk: _____cdyr______ hTmax(m)  _dhT(m)  _Dddoy");
                # reset the min at the max, so can scan for new min from now on ..
                &setmin();
            } else {
                printf (STDOUT " failed --\n") if ($verbose);
                $is_max=0;
            }
        } # if ndata > n_thres_up+1
        
        ## through detection
        # Important: +1 required here to accumulate enough values in @last_slopedn_vals
        if($ndata > $n_thres_dn+1) {
            # for through scanning - trigger on slope change from ($n_thres_dn consecutive +) to (-) after a minimum
      
            # following check only returns 1 if **all but the last** elements in last_slopedn_vals are 1 (cond met)
            $through_cond_met=1;
            # important: do *not* use current point ! we want it have a neg slope so peak is hard-coded  @ last point ..
            # yes, yes, yes.. # array elements increased in test above, hence no '-1' below (and line above still holds)
            for($i=0;$i<$n_thres_dn;$i++){
                $through_cond_met *= $last_slopedn_vals[$i];
            }
            # then clean array at the bottom
            shift(@last_slopedn_vals);
            printf (STDOUT " ndata=%5d  lvl=%+7.4f  dhdt_mph=%+8.4f  through_cond_met=%1d nspate=%1d  -- through conds: ",
                            $ndata,$lvl,$dhdt_mph,$through_cond_met,$nspate)  if ($verbose);
            if($dhdt_mph <= $thres_dn && $peak_cond_met == 1 && $nspate > 0){
                printf (STDOUT " passed ++++++") if ($verbose);
                $is_min=1;
                # $lvl_delat is unique to peaks in spates - comment out here
                $lvl_delta_dn = $lvl_min - $lvl_max;
                # if($lvl_delta > $dh_max){
                # 	  $dh_max = $lvl_delta;
                # }
                $ddoy_delta = $ddoy_min - $ddoy_max;
                if($ddoy_delta < 0) {
                    $ddoy_delta += &dysize($YY-1);
                }
                # now that through was found, can close up entry on new spate
                # output in two steps: 1 (above) - the start of the spate; 2 (here): when peak found
                printf (STDOUT " to %+7.3fm on %4d%02d%02d %02d%02d (dh=%6.3fm over %6.3f days)",
                                $lvl_max,$YY_max,$MM_max,$DD_max,$hh_max,$mm_max,$lvl_delta_dn,$ddoy_delta_dn);
                # reset min to here, so as to look for next min down from the peak
                # if($through_passed == 1){
                # 	  printf (STDOUT "\n                                                                            ");
                printf (ODSLF "\n                                                                            ");
                # }
                # 141021: comment for now ("0,>1 nspates" problem)
                # printf (ODSF "%15.10f %+8.4f  %+7.3f  %6.3f  ",
                # 	$cdyr_min,$lvl_min, $lvl_delta_dn,$ddoy_min);
                printf (ODSLF "tr: %15.10f %+8.4f  %+7.3f  %6.3f",
                              $cdyr_min,$lvl_min, $lvl_delta_dn,$ddoy_min);
                # printf (ODSFL "tr: _____cdyr______ hTmax(m)  _dhT(m)  ddoy_at_min\n");
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
    printf (ODF "%02d/%02d/%4d %02d:%02d, %+8.4f, %15.10f, %12.7f, %7.3f, ",
                $MM,$DD,$YY,$hh,$mm,$lvl,$cdyr,$cdyr-$YY0,$ddoy); # $cdoy %5.1f
    printf (ODDF "%02d %02d %4d %02d %02d  %+8.4f %15.10f %12.7f %7.3f  ",
                $MM,$DD,$YY,$hh,$mm,$lvl,$cdyr,$cdyr-$YY0,$ddoy);
    # printf (ODDF "Legend:\nMM DD YYYY hh mm  __hT(m)_ _____cdyr______ __cdyr-YY0__ __ddoy_  ");
	
    printf (ODF  " %+9.5f, %+9.5f",$dhdt_mph,$dhdt_cpm);
    printf (ODDF " %+9.5f %+9.5f",$dhdt_mph,$dhdt_cpm,$above_thres,$new_spate);  #### <=== #BUG1# ?!? two fields not printed out here ###
    # printf (ODDF " _dhdt_mph dhdt_cmpm");
  
    # printf (ODF  " , %+9.2E, %1d, %1d, %1d, %1d, %1d, %1d, %1d\n",$DSL,$up_met,$is_max,$dn_met,$is_min,$above_thres,$n_not_above_thres,$new_spate);
    # printf (ODDF "  %+9.2E  %1d %1d  %1d %1d  %1d %1d %1d\n",$DSL, $up_met,$is_max,$dn_met,$is_min,$above_thres,$n_not_above_thres,$new_spate);
  
    printf (ODF  " , %+9.2E, %1d, %1d, %1d, %1d,\n",$DSL,$up_met,$is_max,$dn_met,$is_min);
    printf (ODDF "  %+9.2E  %1d %1d  %1d %1d  ",$DSL, $up_met,$is_max,$dn_met,$is_min);
    # printf (ODDF "  _DeltaSL_  For here on a galore of 1/0 flags, in this order:\n");
    # printf (ODDF "up_met is_max  dn_met is_min  ");
  
    printf (ODF  "  %+7.1f, ",$dh_local);
    printf (ODF  "  %1d,  %1d, %1d, %1d, %1d,",$above_thres,$in_spate,$in_spate_last,$in_spate_last_but1,$in_spate_last_but2);
    printf (ODF  "  %1d, %1d\n",$n_not_in_spate,$new_spate);

    printf (ODDF "  %+7.1f ",$dh_local);
    # printf (ODDF "  +7.1f: dh_local ");
    printf (ODDF "  %1d  %1d %1d %1d %1d",$above_thres,$in_spate,$in_spate_last,$in_spate_last_but1,$in_spate_last_but2);
    # printf (ODDF "  above_thres in_spate in_spate_last in_spate_last_but1 in_spate_last_but2");
    printf (ODDF "  %1d %1d\n",$n_not_in_spate,$new_spate);
    # printf (ODDF "  n_not_in_spate new_spate\n--- End of Legend ---\n");


    # put here all updates that must be done before moving to the next point        
    $YY_last=$YY;
    $cdyr_last=$cdyr;
    $lvl_last=$lvl;
    $dhdt_mph_last=$dhdt_mph;
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

printf (STDOUT "\n\n%d points processed in %s\n",$ndata,$tnam);
printf (OSF    "Summary file for cl2dat.pl processing of %s\n\n%d points processed\n",$tnam,$ndata);
$msg=sprintf("%d spates found (dhdt_cpm >= %.3f for %d consec. pts): longest ivl %.2f days, highest ampl %.2f m) [see .spt file (.sptl for long format)]\n",
              $nspate,$spate_thres_up,$n_spate_thres_up,$tsls_d_max,$dh_max);
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("%d gaps found (threshold = %d min): longest %.2f days into %04d%02d%02d %02d:%02d [see .gap file]\n",
                $ngap,$thres_gap,$gap_max/1440.,$YY_gmax,$MM_gmax,$DD_gmax,$hh_gmax,$mm_gmax);
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("%d possible data overlaps found\n",
              $novlap);
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("Absolute extrema in level in this data:\n");
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("  min: %+7.3f m  at cdyr=%10.5f [%s]\n  max: %+7.3f m  at cdyr=%10.5f [%s]\n",
              $lvl_abs_min, $lvl_abs_min_cdyr, $lvl_abs_min_ymdhs, $lvl_abs_max, $lvl_abs_max_cdyr, $lvl_abs_max_ymdhs);
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("Absolute extrema in rate of change of level in this data:\n");
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);
$msg=sprintf ("  min: %+7.3f m/h  at cdyr=%10.5f [%s] (lvl=%+7.3f m)\n  max: %+7.3f m/h  at cdyr=%10.5f [%s] (lvl=%+7.3f m)\n\n",
              $dhdt_abs_min, $dhdt_abs_min_cdyr, $dhdt_abs_min_ymdhs, $dhdt_abs_min_lvl, 
              $dhdt_abs_max, $dhdt_abs_max_cdyr, $dhdt_abs_max_ymdhs, $dhdt_abs_max_lvl);
printf (STDOUT "%s",$msg);
printf (OSF    "%s",$msg);

close(OSF);


############# this is the end of main ---- procedure definitions follow ###############
#
# Note added 160416 JF on date and time formats (DTF)s
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
# 
# Ordinal dates 'YYYY-DDD' or 'YYYYDDD' provide a simple form for occasions when the 
# arbitrary nature of week and month definitions are more of an impediment than an aid,
# for instance, when comparing dates from different calendars. As represented above, 
# [YYYY] indicates a year. [DDD] is the day of that year, from 001 through 365 (366 in
# leap years). For example, "1981-04-05" is also "1981-095"

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
################################################################################
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
sub DoYR { # day, month, year
  local ($day,$mon,$year,$i,$j) = (@_[0],@_[1],@_[2],0,0);
  return -1 if ($day < 1);
  return -1 if (($day > $mdays[$mon-1]) && (&dysize($year) == 365));
  return -1 if (($day > 29) && ($mon == 2) && (&dysize($year) == 366));
  # add extra day if past Feb and in a leap year
  # THIS NEEDS TO BE TESTED - I HAD A CASE WHERE THE  () ? : CONSTRUCT FAILED
  $j = (($mon > 2) && ( &dysize ($year) == 366)) ? 1 : 0 ;
  for($i=1 ; $i < $mon ; $i++) { $j += $mdays[$i-1] ; }
  return ($j + $day ) ;
}

# dysize (year)  => number of days in year || -1
sub dysize { 
  local($y,$yr) = (@_[0],365) ;
  return -1 if ($y < 0 ) ;
  return 347 if ($y == 1752);
  # $y += 1900 if($y < 1970) ;
  $yr = 366 if((($y % 4) == 0) && ( ($y % 100) || (($y % 400)==0) )) ;
  return  $yr ;
}

# set current values to new maximum
sub setmax {
	$MM_max=$MM;
	$DD_max=$DD;
	$YY_max=$YY;
	$hh_max=$hh;
	$mm_max=$mm;
	$lvl_max=$lvl;
	$ddoy_max=$ddoy;
	$cdyr_max=$cdyr;
}

# set current values to new minimum
sub setmin {
	$MM_min=$MM;
	$DD_min=$DD;
	$YY_min=$YY;
	$hh_min=$hh;
	$mm_min=$mm;
	$lvl_min=$lvl;
	$ddoy_min=$ddoy;
	$cdyr_min=$cdyr;
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
        $nline++;
        print ">$_<\n" if ($verbose);
        # next, extract fields per validity range
        
        # 1) start and end dates
        $_ =~ /^(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})\s+(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})/
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
        print "rundata file: \n  start: $start_YY$start_MM$start_DD $start_hh:$start_mm\n" if ($verbose);
        print "  end  : $end_YY$end_MM$end_DD $end_hh:$end_mm\n" if ($verbose);
        
        # 2) parameters, one line for each
        # $_ = <RDF>;
        get_next_non_comment_line(\*RDF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$thres_gap\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($rundata_fn);
        $thres_gap_rd=$1;
        print "  thres_gap_rd = $thres_gap_rd\n" if ($verbose);
        
        #### ALL FOLLOWING CALCULATIONS MUST BE CHECKED #BUG7#
        ## not obtain start and end dt in cdyr units                #BUG6# looms here
        $start_cdoy=&DoYR($start_DD,$start_MM,$start_YY);           # current day of the year
        $start_ddoy=$cdoy + (($start_mm/60.)+$start_hh)/24.;        # real time in units of day of the year
        $start_dy=&dysize($start_YY);                               # days in current year
        $start_dy_last=&dysize($start_YY_last);                     # days in "the year of the last (previous) data point"
        $start_cdyr=$start_YY+( (($start_mm/60.)+$start_hh)/24. + $start_cdoy )/$start_dy;  # Digital (real) year coordinate <==this is #BUG6#
        # print "cdoy=$cdoy, dy=$dy, cdyr=$cdyr, cdyr_last=$cdyr_last\n";
        $end_cdoy=&DoYR($end_DD,$end_MM,$end_YY);                   # current day of the year
        $end_ddoy=$cdoy + (($end_mm/60.)+$end_hh)/24.;              # real time in units of day of the year
        $end_dy=&dysize($end_YY);                                   # days in current year
        $end_dy_last=&dysize($end_YY_last);                         # days in "the year of the last (previous) data point"
        $end_cdyr=$end_YY+( (($end_mm/60.)+$end_hh)/24. + $end_cdoy )/$end_dy;  # Digital (real) year coordinate <==this is #BUG6#
        # print "cdoy=$cdoy, dy=$dy, cdyr=$cdyr, cdyr_last=$cdyr_last\n";
                
        ## store in vectors that will be used inside the code
        push(@rundata_start_t,      $start_cdyr);        
        push(@rundata_end_t,        $end_cdyr);        
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
    $found_sp_block=0;  # this is not used at the end: def'd to stop reading once done w/ this sp, but this was not implemented
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
        $nline++;
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
                print "         in_sp_block = $in_sp_block => SKIP upcoming num sub-block\n" if ($verbose);
                skip_num_block();
                next;
            } else {
                print "         in_sp_block = $in_sp_block => PROCESS upcoming num sub-block\n" if ($verbose);
                # do nothing .. will resume with processing of date fields after this nesting of logics
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
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})\s+(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})/
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
        print "db file: \n  start: $start_YY$start_MM$start_DD $start_hh:$start_mm\n" if ($verbose);
        print "  end  : $end_YY$end_MM$end_DD $end_hh:$end_mm\n" if ($verbose);
        
        # 2) parameters, one line for each
        # $_ = <DBF>;
        get_next_non_comment_line(\*DBF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_spate_thres_up\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_spate_thres_up_db=$1;
        print "  n_spate_thres_up_db = $n_spate_thres_up_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$spate_thres_up\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $spate_thres_up_db=$1;
        print "  spate_thres_up_db = $spate_thres_up_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_not_in_spate_req\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_not_in_spate_req_db=$1;
        print "  n_not_in_spate_req_db = $n_not_in_spate_req_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$dh_local_min\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $dh_local_min_db=$1;
        print "  dh_local_min_db = $dh_local_min_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_thres_up\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_thres_up_db=$1;
        print "  n_thres_up_db = $n_thres_up_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$thres_up\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $thres_up_db=$1;
        print "  thres_up_db = $thres_up_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$n_thres_dn\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $n_thres_dn_db=$1;
        print "  n_thres_dn_db = $n_thres_dn_db\n" if ($verbose);
        
        get_next_non_comment_line(\*DBF);
        chop();
        $nline++;
        print ">$_<\n" if ($verbose);
        $_ =~ /^\s+\$thres_dn\s+=\s+(\d+\.\d+|\d+)/ || die_on_syntax_error($db_fn);
        $thres_dn_db=$1;
        print "  thres_dn_db = $thres_dn_db\n" if ($verbose);
        
        #### ALL FOLLOWING CALCULATIONS MUST BE CHECKED #BUG7#
        ## not obtain start and end dt in cdyr units                #BUG6# looms here
        $start_cdoy=&DoYR($start_DD,$start_MM,$start_YY);           # current day of the year
        $start_ddoy=$cdoy + (($start_mm/60.)+$start_hh)/24.;        # real time in units of day of the year
        $start_dy=&dysize($start_YY);                               # days in current year
        $start_dy_last=&dysize($start_YY_last);                     # days in "the year of the last (previous) data point"
        $start_cdyr=$start_YY+( (($start_mm/60.)+$start_hh)/24. + $start_cdoy )/$start_dy;  # Digital (real) year coordinate <==this is #BUG6#
        # print "cdoy=$cdoy, dy=$dy, cdyr=$cdyr, cdyr_last=$cdyr_last\n";
        $end_cdoy=&DoYR($end_DD,$end_MM,$end_YY);                   # current day of the year
        $end_ddoy=$cdoy + (($end_mm/60.)+$end_hh)/24.;              # real time in units of day of the year
        $end_dy=&dysize($end_YY);                                   # days in current year
        $end_dy_last=&dysize($end_YY_last);                         # days in "the year of the last (previous) data point"
        $end_cdyr=$end_YY+( (($end_mm/60.)+$end_hh)/24. + $end_cdoy )/$end_dy;  # Digital (real) year coordinate <==this is #BUG6#
        # print "cdoy=$cdoy, dy=$dy, cdyr=$cdyr, cdyr_last=$cdyr_last\n";
                
        ## store in vectors that will be used inside the code
        push(@db_start_t,              $start_cdyr);        
        push(@db_end_t,                $end_cdyr);        
        push(@db_n_spate_thres_up,     $n_spate_thres_up_db);        
        push(@db_spate_thres_up,       $spate_thres_up_db);        
        push(@db_n_not_in_spate_req,   $n_not_in_spate_req_db);        
        push(@db_dh_local_min,         $dh_local_min_db);        
        push(@db_n_thres_up,           $n_thres_up_db);        
        push(@db_thres_up,             $thres_up_db);        
        push(@db_n_thres_dn,           $n_thres_dn_db);        
        push(@db_thres_dn,             $thres_dn_db);        

        #     $n_spate_thres_up   =     10   # 4  
        #     $spate_thres_up     =      1   # 0   
        #     $n_not_in_spate_req =      3   # 
        #     $dh_local_min       =      3   # 
        #     $n_thres_up         =     10   # 4
        #     $thres_up           =      0   # 
        #     $n_thres_dn         =      4   # 
        #     $thres_dn           =      0   # 

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
