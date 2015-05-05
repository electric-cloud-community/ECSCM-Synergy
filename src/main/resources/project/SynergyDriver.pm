####################################################################
#
# ECSCM::Synergy::Driver  Object to represent interactions with
#        Synergy.
####################################################################
package ECSCM::Synergy::Driver;
@ISA = (ECSCM::Base::Driver);
use ElectricCommander;
use Time::Local;
use HTTP::Date(qw {str2time time2str time2iso time2isoz});
use Cwd;
if ( !defined ECSCM::Base::Driver ) {
    require ECSCM::Base::Driver;
}

if ( !defined ECSCM::Synergy::Cfg ) {
    require ECSCM::Synergy::Cfg;
}

$| = 1;
use strict;

####################################################################
# Object constructor for ECSCM::Synergy::Driver
#
# Inputs
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#
####################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;

    my $cmdr = shift;
    my $name = shift;

    my $cfg = new ECSCM::Synergy::Cfg( $cmdr, "$name" );
    my $sys = $cfg->getSCMPluginName();
    if ( "$sys" ne "ECSCM-Synergy" ) {
        die "SCM config $name is not type ECSCM-Synergy";
    }

    my ($self) = new ECSCM::Base::Driver( $cmdr, $cfg );

    $self->{synergySessions}         = {};       # cached synergy sessions
    $self->{synergyDelimiters}       = {};       # cached delimiters
    $self->{synergyCurrentDelimiter} = undef;    # current delimter

    bless( $self, $class );
    return $self;
}

####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ( $self, $method ) = @_;

    if ($method eq 'getSCMTag' || 
        $method eq 'checkoutCode') {
        return 1;
    } else {
        return 0;
    }
}

sub checkoutCode {
    my ($self,$opts) = @_;
    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
        $opts->{$k}=$row{$k};
    }
    
    # Load userName and password from the credential
    ( $opts->{SynergyUserId}, $opts->{SynergyPassword} ) =
      $self->retrieveUserCredential(
        $opts->{credential},
        $opts->{SynergyUserId},
        $opts->{SynergyPassword}
      );
    my $projectName = $opts->{projectSpec};
    
    #start session
    $self->debug("Starting session");
    $self->start($opts);
    #get project spec
    $self->debug("Retrieving working project");
    my $projectSpec = $self->getWorkingProject($opts);
    if($projectSpec ne ""){
        #A working project already exists
        $self->debug("Synchronizing project: $projectName");
        $self->synchronize($opts);
    }else{
        $self->debug("Checking out project: $projectName");
        $self->checkoutProject($opts);
        $self->debug("Retrieving working project");
        $projectSpec = $self->getWorkingProject($opts);
    }
    $self->debug("Reconfiguring project $projectName");
    $self->reconfigure($opts);
    if($opts->{dest} && $opts->{dest} ne ""){
        my $workArea = $self->getWorkArea($opts);
        $self->debug("Work area is $workArea");
        $self->debug("Copying files from $workArea to $opts->{dest}");
        print "Copying files from $workArea to $opts->{dest}";
        my $copyCmd = qq{xcopy "$workArea" "$opts->{dest}" /s /i /y};
        if(!$self->isWindows()){
            if(!-d $opts->{dest}){
                mkdir($opts->{dest}) or die $!;
            }
            $copyCmd = qq{cp -R "$workArea" "$opts->{dest}"};
        }
        $self->executeCmd($copyCmd,{LogCommand => 0, LogResult => 0});
    }
    $self->debug("Ending session");
    $self->endSession($opts);
}

####################################################################
# get scm tag for sentry (continuous integration)
####################################################################

####################################################################
# getSCMTag
#
# Get the latest changelist on this branch/client
#
# Args:
# Return: a string representing the latest changes
#
####################################################################
sub getSCMTag {
    my ( $self, $opts ) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row  = $self->getCfg()->getRow($name);
    foreach my $k ( keys %row ) {
        $self->debug("Reading $k=$row{$k} from config");
        $opts->{$k} = "$row{$k}";
    }

    # Load userName and password from the credential
    ( $opts->{SynergyUserId}, $opts->{SynergyPassword} ) =
      $self->retrieveUserCredential(
        $opts->{credential},
        $opts->{SynergyUserId},
        $opts->{SynergyPassword}
      );

    if ( length( $opts->{projectSpec} ) == 0 ) {
        $self->issueWarningMsg("*** No Synergy project was specified.");
        return ( undef, undef );
    }

    # Set up the CM Synergy Session
    my $synergySession = $self->start($opts);
    if ( !$synergySession ) {
        $self->issueWarningMsg("*** Unable to start a CCM session.");
        return ( undef, undef );
    }

    #  Get the most recent change
    my $lastAttempted = $opts->{LASTATTEMPTED};
    my $newCheckinTime;
    $newCheckinTime = $self->SynergyGetChangeTime($opts, $lastAttempted );
    $self->debug("Ending session");
    $self->endSession($opts);
    my $changeTimestamp = str2time($newCheckinTime);
    $changeTimestamp = 0 unless ( defined $changeTimestamp );
    return ( $newCheckinTime, $changeTimestamp );
}

#-------------------------------------------------------------------------
#  SynergyGetChangeTime
#
#  Run the query to see if there are new tasks in the time provided.
#  If no previous time is provided, return the time of the last task
#
#   Params:
#
#       previousTimeString  -   starting point for the query
#
#   Returns:
#       returnTimeString    -   this string represents the time of the most
#                               recent task.  It can be used for enforcing the
#                               quiet period and as a basis a subsequent query.
#
#-------------------------------------------------------------------------
sub SynergyGetChangeTime {
    my ( $self, $opts, $previousTimeString) = @_;
    my @query = ();
# Run the Synergy query command
#   sample command & response
#   ccm query -u "has_attr('completion_date') and type='task' and status='completed'" -f "%name %completion_date"
#   task1   Monday, June 30, 2008 4:39:35 PM
    push(@query,qq{has_attr('completion_date') and type='task' and status='completed'});
    if($previousTimeString && $previousTimeString ne ""){
        push(@query,qq{and completion_date>time('$previousTimeString')});
    }

    my $query = join(" ",@query);
    my $command = $self->query($opts, $query, q{"%name %completion_date"});

    # run Synergy
    my $cmndReturn = $self->executeCmd($command, { LogCommand => 1, LogResult => 1, IgnoreError => 1 });
    
    #  Search the returned lines looking for the time of the newest task
    my $newestTime       = 0;
    my $returnTimeString = "";
    foreach my $line ( split( /\n/, $cmndReturn ) ) {
        if ( $line =~ m/([a-zA-Z0-9]*)\s+(.*)/) {

            # save the newest time
            my $taskNumber = $1;
            my $timeString = $self->synergy2sentrytime($2);
            my $time       = str2time($timeString);
            if ( $time > $newestTime ) {
                $newestTime       = $time;
                $returnTimeString = $timeString;
            }
        }
    }
    return ($returnTimeString);
}

#converts the synergy date format to the sentry format. e.g Friday, July 04, 2008 12:00:01 AM => Friday, 04-Jul-2008 12:00:01
sub synergy2sentrytime{
  my ( $self, $date) = @_;
  $date =~ m/([a-zA-Z]*),\s([a-zA-Z]*)\s(\d+),\s(\d+)\s(.*)/;
  my ($day, $month, $dayNumber, $year, $hour) = ($1, $self->replaceMonth($2), $3, $4, $self->twelveTo24($5));
  return qq{$day, $dayNumber-$month-$year $hour}
}

#return a month in short format
sub replaceMonth{
  my ( $self, $month) = @_;
  my %replacements = (
         qq{January}    => qq{Jan},
         qq{February}   => qq{Feb},
         qq{March}      => qq{Mar},
         qq{April}      => qq{Apr},
         qq{June}       => qq{Jun},
         qq{July}       => qq{Jul},
         qq{August}     => qq{Aug},
         qq{September}  => qq{Sep},
         qq{October}    => qq{Oct},
         qq{November}   => qq{Nov},
         qq{December}   => qq{Dec},
         );
  while ( my ($key, $value) = each(%replacements) ) {
    if($month =~ m/$key/){
      $month =~ s/$key/$value/;
      return $month;
    }
  }
  return $month;
}

#convert the 12 h format to 24 h format e.g 1:00 pm => 13:00
sub twelveTo24{
  my ( $self, $time) = @_;
  $time =~ m/(.*) (.*)/;
  if(lc($2) eq "am"){
    $time =~ s/am//i;
    return $time;
  }
  $time =~ m/(\d+)\:/;
  my $hour = $1;
  my $newHour = $hour + 12;
  $time =~ s/$hour/$newHour/;
  $time =~ s/pm//i;
  return $time;
}

#Start a session Synergy
sub start{
    my ( $self, $opts ) = @_;
    
    #ccm start -nogui -m -nogui -q <username> -pw <password> -r <role>
    my @args = ();
    push(@args,"ccm start -nogui -m -q");
    if($opts->{SynergyDatabasePath} && $opts->{SynergyDatabasePath} ne ""){
        push(@args,qq{-d "$opts->{SynergyDatabasePath}"});
    }
    if($opts->{SynergyUserId} && $opts->{SynergyUserId} ne ""){
        push(@args,qq{-n "$opts->{SynergyUserId}"});
    }else{
        print "username can't be null";
        exit;
    }
    if($opts->{SynergyPassword} && $opts->{SynergyPassword} ne ""){
        push(@args,qq{-pw "$opts->{SynergyPassword}"});
    }else{
        print "password can't be null";
        exit;
    }
    if($opts->{SynergyUserRole} && $opts->{SynergyUserRole} ne ""){
        push(@args, qq{-r "$opts->{SynergyUserRole}"})
    }
    my $here = cwd;
    push(@args, qq{-home "$here"});
    my $cmd = join(" ",@args);
    $opts->{ccmAddr} = $self->executeCmd($cmd);
}

#Get a working project whose predecessor is given.
sub getWorkingProject{
    my ( $self, $opts ) = @_;

    my @query = ();
    if($opts->{SynergyUserId} && $opts->{SynergyUserId} ne ""){
        push(@query,qq{owner='$opts->{SynergyUserId}'})
    }
    #status
    push(@query,qq{and status='working'});
    #type
    push(@query,qq{and type='project'});
    if($opts->{projectSpec} && $opts->{projectSpec} ne ""){
        push(@query,qq{and name='$opts->{projectSpec}'});
    }
    my $query = join(" ",@query);
    
    my $cmd = $self->query($opts, $query, q{%objectname});
    print "Executing query.\n";
    $opts->{projectSpec} = $self->executeCmd($cmd);
}

#Create commandline for query.
sub query{
    my ( $self, $opts, $query, $format ) = @_;
    $self->configureEnvironment($opts);
    my @args = ();
    push(@args,"ccm query -u");
    if($query && $query ne ""){
        push(@args,qq{"$query"});
    }
    if($format && $format ne ""){
        push(@args,qq{-f $format});
    }
    return join(" ",@args);
}

#sets the required env variables that synergy needs
sub configureEnvironment{
    my ( $self, $opts ) = @_;
    if($ENV{'CCM_ADDR'} eq ""){
        $ENV{'CCM_ADDR'} = $opts->{ccmAddr};
    }
}

#Synchronize a given project.
sub synchronize{
    my ( $self, $opts ) = @_;
    $self->configureEnvironment($opts);
    my @args = ("ccm sync");
    push(@args,"-r");#Recursive
    if($opts->{projectSpec} && $opts->{projectSpec} ne ""){
        push(@args, qq{-p "$opts->{projectSpec}"});
    }
    my $syncCommand = join(" ",@args);
    $self->executeCmd($syncCommand);
}

#Checkout a given project.
sub checkoutProject{
    my ( $self, $opts ) = @_;
    
    $self->configureEnvironment($opts);
    my @args = ();
    
    push(@args, "ccm co");

    if($opts->{projectSpec} && $opts->{projectSpec} ne ""){
        push(@args, qq{-p "$opts->{projectSpec}"});
    }
    
    if($opts->{subprojects} && $opts->{subprojects} eq 1){
        push(@args, "-subprojects");
    }

    if($opts->{release} && $opts->{release} ne ""){
        push(@args, qq{-release "$opts->{release}"});
    }
    
    if($opts->{purpose} && $opts->{purpose} ne ""){
        push(@args, qq{-purpose "$opts->{purpose}"});
    }
    
    if($opts->{Version} && $opts->{Version} ne ""){
        push(@args, "-t $opts->{Version}");
    }
    
    #if($opts->{Relative} && $opts->{Relative} eq 1){
    #    push(@args, "-rel");
    #}
    
    if($opts->{dest} && $opts->{dest} ne ""){
        push(@args, qq{-path "$opts->{dest}"});
    }
    
    my $coCommand = join(" ",@args);
    $self->executeCmd($coCommand);
}

#Reconfigure a project.
sub reconfigure{
    my ( $self, $opts ) = @_;
    $self->configureEnvironment($opts);
    my @cmd = ("ccm reconfigure");
    push(@cmd,"-recurse");
    if($opts->{projectSpec} && $opts->{projectSpec} ne ""){
        push(@cmd, qq{-p "$opts->{projectSpec}"});
    }
    my $command = join(" ",@cmd);
    $self->executeCmd($command);
}

#returns the current working area for a project
sub getWorkArea{
    my ( $self, $opts ) = @_;
    $self->configureEnvironment($opts);
    my @cmd = ("ccm wa");
    if($opts->{projectSpec} && $opts->{projectSpec} ne ""){
        push(@cmd, qq{-show "$opts->{projectSpec}"});
    }
    my $command = join(" ",@cmd);
    my $result = $self->executeCmd($command);
    $result =~ m/'(.*)'/;
    return $1;
}

#Stop a ccm session.
sub endSession{
    my ($self) = @_;
    print "Ending session.\n";
    $self->executeCmd("ccm stop");
}

#Executes a command and returns results
sub executeCmd{
    my ($self, $command, $options) = @_;
    if ($options eq '') {
        $options = {LogCommand => 1, LogResult => 1}; 
	}
    my $out = $self->RunCommand($command, $options);           
	return $out;
}

1;
