#######################################################################################################
#
# 78_ZendureLAN.pm 
#
# This module uses the local HTTP-REST-API of Zendure devices to query current status values ​​
# and send commands. The properties are defined in the project Github-Zendure-zenSDK
# https://github.com/Zendure/zenSDK/blob/main/docs/en_properties.md
#
# todo: limit als attribut definieren ?!? mögliche set-befehle durch readings checken
#
#######################################################################################################
# v1.0.1 - 26.04.2026 DevStateIcon, Timestamps als Klartext, remainOutTime als DD:HH:MM
# v1.0.0 - 24.03.2026 Zendure Rest API aus https://github.com/Zendure/zenSDK/blob/main/README.md
#######################################################################################################

package main;

use strict;
use warnings;

use HttpUtils;

use vars qw(%FW_webArgs);

## try to use JSON::XS, otherwise use own decoding sub
my $json_xs_available = 1;
eval "use JSON::XS qw(decode_json); 1" or $json_xs_available = 0;

my $ZendureLAN_version = 'v1.0.1 - 26.04.2026';

my $ZendureLANTable =
{ 'gridReverse' => 	{ '0' => 'disabled','1' => 'allow',	'2' => 'forbidden' },
  'gridOffMode' => 	{ '0' => 'normal', 	'1' => 'eco', 	'2' => 'off' },
  'passMode' => 	{ '0' => 'auto', 	'1' => 'on', 	'2' => 'off' },
  'fanSpeed' => 	{ '0' => 'auto', 	'1' => 'normal','2' => 'fast'},
  'heatState' => 	{ '0' => 'off', 	'1' => 'heating' },
  'acMode' =>		{ '1' => 'input', 	'2' => 'output' },
  'smartMode' => 	{ '0' => 'off', 	'1' => 'on' },
  'state' => 		{ '0' => 'standby', '1' => 'charge','2' => 'discharge'}, 
  'packState' => 	{ '0' => 'standby', '1' => 'charge','2' => 'discharge'},
  'socStatus' => 	{ '0' => 'idle', 	'1' => 'calibration' },
};

my $ZendureLANRange =
{ 'outputLimit' => { 'min' => 0, 'max' => 800 },
  'inputLimit' 	=> { 'min' => 0, 'max' => 800 },
  'minSoc' 		=> { 'min' => 0, 'max' => 50  },
  'socSet' 		=> { 'min' => 70,'max' => 100 }
};

###################################### Forward declarations ###########################################

sub ZendureLAN_Initialize($);			# define the functions to be called 
sub ZendureLAN_Define($$);				# handle define 
sub ZendureLAN_Undefine($$);			# handle undefine a device, remove timers
sub ZendureLAN_Set($$@);				# handle the set commands of devices
sub ZendureLAN_Get($$@);				# handle the get commands of devices
sub ZendureLAN_Poll($);					# create get-request
sub ZendureLAN_Call($$$;$$);			# request the REST-API
sub ZendureLAN_Response($$$);			# check the response 
sub ZendureLAN_Parse($$$);				# parse the response

#######################################################################################################

sub ZendureLAN_Initialize($)
{
	my ($hash) = @_;
	$hash->{DefFn}    = 'ZendureLAN_Define';
	$hash->{UndefFn}  = 'ZendureLAN_Undefine';
	$hash->{SetFn}    = 'ZendureLAN_Set';
	$hash->{GetFn}    = 'ZendureLAN_Get';
	$hash->{AttrFn}   = 'ZendureLAN_Attr';
}

############################  handle define: check syntax, prepare attributes##########################

sub ZendureLAN_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	
	return "Syntax: define <NAME> ZendureLAN <IP> <Serial-Number>" if (int(@a) != 4 );
	my $name = $a[0]; # a[0]=name; a[1]=ZendureLAN; a[2]..a[3]= parameters
	return "invalid <IP> ! Syntax: define <NAME> ZendureLAN <IP> <Serial-Number>"  if ($a[2] !~ /^(\d{1,3}\.){3}\d{1,3}$/ );
	$hash->{IP}   = $a[2];
	$hash->{SN}   = $a[3];
	$hash->{INTERVAL} = 10;
	$hash->{VERSION} = $ZendureLAN_version;
	$hash->{DEF} = $hash->{IP}.' '.$hash->{SN};
	
	setDevAttrList($name, 'interval saveJSON:1,0 '. $readingFnAttributes);
	
	if ($init_done) {
		CommandAttr(undef, '-silent '.$name.' [0-5]:measure_battery_0@red [6-9]:measure_battery_0@orange [1-3]\d:measure_battery_25@orange '.
		'[4-6]\d:measure_battery_50@green [7-9]\d:measure_battery_75@green 100:measure_battery_100@green') if(!AttrVal($name,"devStateIcon",""));
		CommandAttr(undef, '-silent '.$name.' stateFormat electricLevel') if(!AttrVal($name,"stateFormat",""));	
		CommandAttr(undef, '-silent '.$name.' room Zendure_Device') if(!AttrVal($name,"room",""));
		CommandAttr(undef, '-silent '.$name.' webCmd outputLimit:inputLimit:acMode:minSoc:socSet:gridOffMode:gridReverse') if(!AttrVal($name,"webCmd",""));
		CommandAttr(undef, '-silent '.$name.' webCmdLabel outputLimit<br>:inputLimit<br>:acMode<br>:minSoc<br>:maxSoc<br>:Steckdose<br>:Netzbezug<br>') if(!AttrVal($name,"webCmdLabel",""));
		CommandAttr(undef, '-silent '.$name.' event-on-change-reading .*') if(!AttrVal($name,"event-on-change-reading",""));
		CommandAttr(undef, '-silent '.$name.' interval 10') if(!AttrVal($name,"interval",""));
	}	
	return undef;
}

############################  handle undefine: remove timer  ##########################################

sub ZendureLAN_Undefine($$)
{
	my ($hash, $arg) = @_;
	RemoveInternalTimer($hash);
	return undef;
}

############################  verify and handle set commands  #########################################

sub ZendureLAN_Set($$@)
{
	my ($hash, $name, @a) = @_;
	return undef if not scalar @a;
	my $setlist = 
	'outputLimit:slider,0,1,800 '.
	'inputLimit:slider,0,1,800 '.
	'minSoc:selectnumbers,0,5,50,0,lin '.
	'socSet:selectnumbers,70,5,100,0,lin '.
	
	'acMode:input,output '.
	'smartMode:on,off '.
	'gridReverse:disabled,allow,forbidden '.
	'gridOffMode:normal,eco,off '.
	'rpc' ;
	
	my $cmd = shift @a;
	
	if (int(@a)==1) {
		my $value = shift @a;
		if ($cmd =~ /^(outputLimit|inputLimit|minSoc|socSet)$/) {
			return "invalid argument $cmd : $value, choose one of $setlist" if ($value !~ /^-?\d+$/ );
			if ($value < $ZendureLANRange->{$cmd}{'min'} || $value > $ZendureLANRange->{$cmd}{'max'}) {
				return "out of range $cmd : $value, choose a value between $ZendureLANRange->{$cmd}{'min'} and $ZendureLANRange->{$cmd}{'max'}" ;
			}
			Log3 $hash, 4, "$name: Set $cmd = $value";
			$value = $value * 10 if ($cmd =~ /^(minSoc|socSet)$/); 
			ZendureLAN_Call($hash,'POST','/properties/write',$cmd,$value);
			return;
		} elsif ($cmd =~ /^(acMode|gridReverse|gridOffMode|smartMode)$/) {
			if (defined($ZendureLANTable->{$cmd})) {
				foreach my $key (sort keys %{$ZendureLANTable->{$cmd}}){
					if ($ZendureLANTable->{$cmd}{$key} eq $value) {
						Log3 $hash, 4, "$name: Set $cmd = $value ($key)";
						$value = $key;
						ZendureLAN_Call($hash,'POST','/properties/write',$cmd,$value);
						return;
					}
				}
			}
		} elsif ($cmd eq "rpc"){
			ZendureLAN_Call($hash,'POST','/rpc',$cmd,$value);
			return;
		}
	} 
	return "unknown argument $cmd, choose one of $setlist";
}

############################  verify and handle get commands  #########################################

sub ZendureLAN_Get($$@)
{
	my ($hash, $name, @a) = @_;
	return undef if not scalar @a;
	my $cmd = shift @a;
	my $getlist = 'forceUpdate:noArg rpc:HA.Mqtt.GetStatus,HA.Mqtt.GetConfig';
	
	if ($cmd eq "forceUpdate" ) {
		Log3 $hash, 4, "$name: Get $cmd";
		ZendureLAN_Call($hash,'GET','/properties/report');
		return;
	}
	if ($cmd eq "rpc" ) {
		my $val = shift @a;
		if (defined($val)) {
			Log3 $hash, 4, "$name: Get /rpc?method=$val";
			ZendureLAN_Call($hash,'GET','/rpc?method='.$val);
		}
		return;
	}	
	return "unknown argument $cmd, choose one of $getlist";		
}

#######################################################################################################

sub ZendureLAN_Poll($)
{
	my ($hash) = @_;
	ZendureLAN_Call($hash,'GET','/properties/report');
}

######################  initiate a non-blocking call to Zendure Rest-API ##############################

sub ZendureLAN_Call($$$;$$)
{
	my ($hash, $method, $path, $cmd, $value) = @_;		

	my $header;
	my $data;
	my $name = $hash->{NAME};
	if ( $method eq 'POST' ) {
		$header = { 'Content-Type' => 'application/json' };
		if (defined($cmd) && defined($value)) {
			my $val = ($value =~ /^-?\d+(\.\d+)?$/) ? 0 + $value : $value;
			my $body;
			if ($cmd eq "rpc") {
				$body = { sn => $hash->{SN}, 'method' => 'HA.Mqtt.SetConfig', 'params' => { 'config' => $val }};
				readingsSingleUpdate($hash,'_last_set','request',1);
			} else {
				$body = { sn => $hash->{SN}, 'properties' => { $cmd => $val } };
			}
			$data = toJSON($body);
			Log3 $hash, 4, "$name: Set $cmd = $val";
			readingsSingleUpdate($hash,'_last_set',$cmd.'='.$val,1);
		}
	}
	RemoveInternalTimer($hash);	
	HttpUtils_NonblockingGet(
	{ 	
		callback => \&ZendureLAN_Response,
		method => $method,
		hash => $hash,
		url => 'http://'.$hash->{IP}.$path , 
		timeout => 5, 
		header => $header, 
		data => $data
	});	
	readingsSingleUpdate($hash,'_last_call', $method.' -> '.$path ,1);
	my $interval = int(AttrVal($name, "interval", 0));
	if ($interval) {
		InternalTimer(gettimeofday()+$interval, 'ZendureLAN_Poll', $hash, 0); 
		readingsSingleUpdate($hash, '_polling', 'active ('.$interval.' sec)', 1 );
	} else {
		readingsSingleUpdate($hash, '_polling', 'disabled', 1 );
	}
	return;	
}

######################  handle the response of the request############## ##############################

sub ZendureLAN_Response($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	$hash->{VERSION} = $ZendureLAN_version;
	
	if ($err || $param->{code} != 200) {
		my $errtxt = "ZendureLAN ($param->{method}): ";
		$errtxt .= $err if ($err);
		$errtxt .= " HTTP-Status-Code=" . $param->{code} if (defined($param->{code}));
		$errtxt .= " Response: " . $data if (defined($data));
		Log3 $hash, 2, $errtxt;
		readingsSingleUpdate($hash,'_last_error',$errtxt,1);
		return;
	} 
	
	if (defined($data) && $data ne '') {
		readingsSingleUpdate($hash,'jsonRawData',$data,1) if (AttrVal($hash->{NAME},'saveJSON',undef));
		my $json;		
		## transform json to perl object -> use JSON::XS (=fastest), otherwise use an own awesome method
		if ($json_xs_available) {
			$json = eval { JSON::XS->new->boolean_values("false","true")->decode($data) };
			if ($@) {
				Log3 $hash, 2, 'Error using JSON::XS. To use the faster JSON::XS you have to update to the latest version. Try: "sudo apt-get install -y libjson-xs-perl" in the linux shell. Currently an alternative method will be used.';
				$json_xs_available = 0;
			};
		}
		if (!$json_xs_available) {
			$data =~ s/":/"=>/g;
			($json) = eval $data ;
		}
		##parse
		readingsBeginUpdate($hash);
		ZendureLAN_Parse($hash,$json,($param->{method} eq 'POST')?'_last_response_':'') if (ref($json) eq "HASH");
		readingsEndUpdate($hash, 1);
	}
}
	
sub ZendureLAN_Parse($$$) {
	my ($hash, $json, $level) = @_;
	foreach my $key (sort keys %{$json}) {
		next if (!defined($json->{$key}));
		if (ref($json->{$key}) eq "HASH") {
			## if Hash -> go deeper in the next level
			ZendureLAN_Parse($hash,$json->{$key},$level);
		} elsif (ref($json->{$key}) eq "ARRAY") {
			## if Array -> crawl the array
			foreach my $mp (sort keys @{$json->{$key}}){
				ZendureLAN_Parse($hash,$json->{$key}[$mp],'bat'.$mp.'_');
			}
		} elsif (!ref($json->{$key})) {	
			## prepare values
			my $value = $json->{$key};
			if ($key =~ /^(hyperTmp|maxTemp)$/ && $value =~ /^\d+$/) { 
				$value = sprintf("%.1f", ($value - 2731) / 10.0 );
			} 
			elsif ($key =~ /^(BatVolt|minVol|maxVol|totalVol)$/ && $value =~ /^\d+$/) { 
				$value = sprintf("%.2f", $value / 100.0 );
			}
			elsif ($key eq "batcur" && $value =~ /^\d+$/) {
				$value = $value & 0xffff;
				$value = ($value & 0x8000) ? ($value - 0x10000) : $value;
				$value = sprintf("%.1f", $value / 10.0);
			} elsif ($key =~ /^(socSet|minSoc)$/ && $value =~ /^\d+$/) {
				$value = sprintf("%.1f", $value / 10.0 );
			} elsif ($key =~ /^(timestamp|ts)$/ && $value =~ /^\d+$/) {
				readingsBulkUpdate($hash, $level.$key.'_txt', FmtDateTime($value))
			} elsif ($key eq 'remainOutTime' && $value =~ /^\d+$/) {
				my $tage = int($value/1440);
				my $stdn = int(($value-($tage*1440))/60);
				my $minu = $value-($tage*1440)-($stdn*60);
				readingsBulkUpdate($hash, $level.$key.'_txt', $tage.'d '.$stdn.'h '.$minu.'m');
			} elsif (defined($ZendureLANTable->{$key}) && defined($ZendureLANTable->{$key}{$value})){
				$value = $ZendureLANTable->{$key}{$value};
			}
			readingsBulkUpdate($hash, $level.$key, $value);			
		}
	}
}
	
##############################  handle attribut changes  ##############################################

sub ZendureLAN_Attr($$)
{
	my ($cmd, $name, $attrName, $attrVal) = @_;
	my $hash = $defs{$name};	
	if ( $attrName eq 'interval' ) {
		if ( $cmd eq 'del' || $attrVal == 0) {
			RemoveInternalTimer($hash);
			$hash->{INTERVAL} = 0;
			readingsSingleUpdate($hash, '_polling', 'disabled', 1 );
		} elsif ( $attrVal >= 10 ) {
			RemoveInternalTimer($hash);
			$hash->{INTERVAL} = $attrVal;
			InternalTimer(gettimeofday()+1, 'ZendureLAN_Poll', $hash, 0);
			readingsSingleUpdate($hash, '_polling', 'active ('.$attrVal.' sec)', 1 );
		} else { ## if interval < 10
			return "Minimum polling interval is 10 seconds.";
		}
		## save jsonRawData in a reading
	} elsif ( $attrName eq 'saveJSON' ) {
		if (( $cmd eq 'del' ) || ( $attrVal == 0 )) {
			CommandDeleteReading(undef,'-q '.$name.' jsonRawData.*');
		}
	}		
	return undef;
}

###############################################################################################
########################################  end of code #########################################
###############################################################################################

1;

=pod
=item device
=item summary    controls Zendure-Devices locally over HTTP-Rest-API  
=item summary_DE steuert Zendure-Ger&auml;te &uuml;ber die lokale HTTP-Rest-API 
=begin html

<a id="ZendureLAN"></a>
<h3>ZendureLAN</h3>
<ul>
  This module uses the local HTTP REST API of Zendure devices to query current status values ​​
  and send commands. The properties are defined in the project 
  <a href="https://github.com/Zendure/zenSDK/blob/main/docs/en_properties.md"
  target="_blank">Github-Zendure-zenSDK</a>
  <br><br>
  <a id="ZendureLAN-define"></a>
  <b>Define</b>
  <ul><ul>
    To define the device, you need the ip-adress and the serial number of the Zendure-Device.
    <code>define &lt;NAME&gt; ZendureLAN &lt;IP adress&gt; &lt;serial number&gt;</code><br>
  </ul></ul>
  <br>
  <b>Set</b>
  <ul><ul>
    <br>
    <a id="ZendureLAN-set-acMode"></a>
    <li><b>acMode</b> [ input | output ] <br>
      Switch between outputmode = discharge and inputmode = charge. 
    </li>
	<br>
    <a id="ZendureLAN-set-inputLimit"></a>
    <li><b>inputLimit</b> [ 0 .. 800 ] <br>
      Set the AC charge inputLimit in Watt.
    </li>
	<br>
    <a id="ZendureLAN-set-outputLimit"></a>
    <li><b>outputLimit</b> [ 0 .. 800 ] <br>
      Set the outputLimit in Watt.
    </li>
	<br>
    <a id="ZendureLAN-set-socSet"></a>
    <li><b>socSet</b> [ 70 .. 100 ] <br>
      Set the target SOC in percent.
    </li>
	<br>
    <a id="ZendureLAN-set-minSoc"></a>
    <li><b>minSoc</b> [ 0 .. 50 ] <br>
      Set the minimum SOC in percent.
    </li>
	<br>
    <a id="ZendureLAN-set-smartMode"></a>
    <li><b>smartMode</b> [ on | off ] <br>
      Enable smartmode: Parameters are not written to flash. Device restores 
	  previous flash values after reboot. Recommended for frequent configuration 
	  changes.
	  Disable smartmode: Parameters are written to flash. A large number of 
	  write operations to the flash memory will affect the lifespan of the device!
    </li>
	<br>
    <a id="ZendureLAN-set-gridReverse"></a>
    <li><b>gridReverse</b> [ disabled | allow | forbidden ] <br>
      Reverse flow control (AC).
    </li>
	<br>
    <a id="ZendureLAN-set-gridOffMode"></a>
    <li><b>gridOffMode</b> [ normal | eco | off ] <br>
      Switches the emergency power outlet. Choose between: Standard Mode, Economic Mode, off
    </li>	
  </ul></ul>
  <br>
  <b>Get</b> 
  <ul><ul>
    <br>
    <a id="ZendureLAN-get-forceUpdate"></a>
    <li><b>forceUpdate</b><br>
      Does an update.
    </li> 
	<br>
    <a id="ZendureLAN-get-rpc"></a>
    <li><b>rpc</b><br>
      Get MQTT-status and MQTT-settings.
    </li> 
  </ul></ul>
  <br>
  <b>Attributes</b>
  <ul><ul>
    <br>
    <a id="ZendureLAN-attr-interval"></a>
    <li><b>interval</b> [ 0 | 10 .. &infin; ]<br>
      Defines the interval in seconds for requesting actual data from the device. 
      The minimum possible interval is 10 seconds to ensure that the device functions 
	  stably. If set to 0, the polling will be disabled. <br>
    </li>
	<br>
    <a id="ZendureLAN-attr-saveJSON"></a>
    <li><b>saveJSON</b> [ 0 | 1 ]<br>
      If saveJSON ist set to 1, the raw data (JSON) will be saved in the reading jsonRawData.<br>
    </li>
  </ul></ul>
</ul>
<br>

=end html
=begin html_DE




=end html_DE

=cut