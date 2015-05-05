my $projPrincipal = "project: $pluginName";
my $ecscmProj     = '$[/plugins/ECSCM/project]';

if ( $promoteAction eq 'promote' ) {

    # Register our SCM type with ECSCM
    $batch->setProperty( "/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@", "Synergy" );

    # Give our project principal execute access to the ECSCM project
    my $xpath = $commander->getAclEntry( "user", $projPrincipal, { projectName => $ecscmProj } );
    if ( $xpath->findvalue( '//code' ) eq 'NoSuchAclEntry' ) {
        $batch->createAclEntry( "user", $projPrincipal, { projectName => $ecscmProj, executePrivilege => "allow" } );
    }

}
elsif ( $promoteAction eq 'demote' ) {

    # unregister with ECSCM
    $batch->deleteProperty( "/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@" );

    # remove permissions
    my $xpath = $commander->getAclEntry( "user", $projPrincipal, { projectName => $ecscmProj } );
    if ( $xpath->findvalue( '//principalName' ) eq $projPrincipal ) {
        $batch->deleteAclEntry( "user", $projPrincipal, { projectName => $ecscmProj } );
    }
}

# Unregister current and past entries first.
$batch->deleteProperty( "/server/ec_customEditors/pickerStep/ECSCM-Synergy - Checkout" );
$batch->deleteProperty( "/server/ec_customEditors/pickerStep/ECSCM-Synergy - Preflight" );
$batch->deleteProperty( "/server/ec_customEditors/pickerStep/Synergy - Checkout" );
$batch->deleteProperty( "/server/ec_customEditors/pickerStep/Synergy - Preflight" );

my %checkout = (
    label       => "Synergy - Checkout",
    procedure   => "CheckoutCode",
    description => "Checkout code from Synergy.",
    category    => "Source Code Management"
);

my %preflight = (
    label       => "Synergy - Preflight",
    procedure   => "Preflight",
    description => "Checkout code from Synergy during Preflight",
    category    => "Source Code Management"
);

@::createStepPickerSteps = ( \%checkout, \%preflight );
