@files = (
    ['//property[propertyName="ECSCM::Synergy::Cfg"]/value', 'SynergyCfg.pm'],
    ['//property[propertyName="ECSCM::Synergy::Driver"]/value', 'SynergyDriver.pm'],
    ['//property[propertyName="createConfig"]/value', 'synergyCreateConfigForm.xml'],
    ['//property[propertyName="editConfig"]/value', 'synergyEditConfigForm.xml'],
    ['//property[propertyName="sentry"]/value', 'synergySentryForm.xml'],
    ['//procedure[procedureName="getSCMTag"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'synergySentryForm.xml'],
    ['//procedure[procedureName="CheckoutCode"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'synergyCheckoutForm.xml'],
    ['//property[propertyName="checkout"]/value', 'synergyCheckoutForm.xml'],	
    ['//property[propertyName="ec_setup"]/value', 'ec_setup.pl'],
);
