#!/usr/bin/perl

# HRreport	Version 1.0
# Daniel Sung   Date: 2-Jun-2020



# Load Database Module
use DBI;
use Date::Simple (':all');


our $today	= today();
our $year       = $1 if($today =~ /^(\d+)\-\d+\-\d+$/);
our $this_month = $1 if($today =~ /^(\d+\-\d+)\-\d+$/);
our $host	= 'localhost';
our $login	= 'root';
our $password	= 'dbpassword';
our $database	= 'sentrifugo';
our $mail_log	= '/tmp/draft.html';
our $sender	= 'sender\@yourdmain.com';
our %list	= ();
our ($which, $mail_command, $cat, $temp_email);
$which				= '/usr/bin/which';
chomp($mail_command		= qx($which mutt));
chomp($cat			= qx($which cat));

if(! $year or ! $this_month){
        die "Fail to define the date information.";
}


# ==============================================
# Connection Database if necessary.
# ==============================================
my $dbh = DBI->connect("DBI:mysql:database=$database;host=$host","$login","$password");

if(!$dbh){
        die "ERROR : Fail to connect the HR databases DBI->errstr()";
}

my $query = $dbh->prepare("select reporting_manager id, reporting_manager_name name from main_employees_summary where isactive = '1' group by reporting_manager");
$query->execute;
my $check = $query->rows;
if($query->rows > 0){
        while(my $record = $query->fetchrow_hashref()){
		my $id = $record->{'id'};
		$list{$id} = $record->{'name'};
        }
}
$query->finish();

foreach my $manager_id (sort keys %list){
	my %colleague = ();
	my $query = $dbh->prepare("select userfullname, emailaddress from main_employees_summary where isactive = '1' and reporting_manager = '$manager_id' order by emailaddress");
	$query->execute;
	if($query->rows > 0){
	        while(my $record = $query->fetchrow_hashref()){
			my $email = $record->{'emailaddress'};
			$colleague{$email} = $record->{'userfullname'};
		}
        }
	$query->finish();
	foreach my $email (sort keys %colleague){
		my $test = $dbh->prepare("select main_employees_summary.user_id from main_employees_summary where main_employees_summary.emailaddress = '$email' and main_employees_summary.user_id NOT IN(select main_employeeleaves.user_id from main_employeeleaves where alloted_year = '$year') and main_employees_summary.isactive = 1");
		$test->execute;
		if($test->rows eq 0){
			my $query = $dbh->prepare("select main_users.userfullname Full_name, main_employees_summary.businessunit_name office_name, main_employees_summary.jobtitle_name jobtitle, main_employees_summary.emp_status_name empstatus, main_employeeleaves.emp_leave_limit Total_avaliable_leaves, main_employeeleaves.used_leaves Used_leaves, (main_employeeleaves.emp_leave_limit - main_employeeleaves.used_leaves) Leave_balance from main_employees, main_users, main_employeeleaves, main_employees_summary  where main_users.id = main_employeeleaves.user_id and main_employees.user_id = main_employeeleaves.user_id and main_employees_summary.user_id = main_employeeleaves.user_id and main_employeeleaves.alloted_year = '$year' and main_employees.isactive = 1 and main_users.emailaddress = '$email'");
			$query->execute;
			if($query->rows > 0){
				while(my $result = $query->fetchrow_hashref){
					$colleague{$email}->{'office'} = $result->{'office_name'};
					$colleague{$email}->{'jobtitle'} = $result->{'jobtitle'};
					$colleague{$email}->{'empstatus'} = $result->{'empstatus'};
					$colleague{$email}->{'totalleave'} = $result->{'Total_avaliable_leaves'};
					$colleague{$email}->{'usedleave'} = $result->{'Used_leaves'};
					$colleague{$email}->{'leavebalance'} = $result->{'Leave_balance'};
				}
			}
			my $query = $dbh->prepare("select from_date, to_date, leavetype_name, appliedleavescount, leavestatus from main_leaverequest_summary where from_date like '$year%' and user_name = '$colleague{$email}' and \(leavestatus = 'Approved' or leavestatus = 'Pending for approval'\) order by from_date");
			$query->execute;
			if($query->rows > 0){
				while(my $result = $query->fetchrow_hashref){
					my $from = $result->{'from_date'};
					my $to = $result->{'to_date'};
					my $type = $result->{'leavetype_name'};
					my $days = $result->{'appliedleavescount'};
					my $status = $result->{'leavestatus'};
					push(@{$colleague{$email}->{'leaverecords'}},"$from|$to|$days|$type|$status");
				}
			}
			$query->finish();
		}else{
			delete($colleague{$email});
		}
	}
	# Generating the email
	my $receiver = '';
	my $fullname = '';
	my $q = $dbh->prepare("select emailaddress from main_users where id = '$manager_id'");
	$q->execute;
	if($q->rows > 0){
		while(my $search = $q->fetchrow_hashref()){
			$receiver = $search->{'emailaddress'};
		}
	}
	$q->finish();
	unlink($mail_log)if(-f $mail_log);
	if($receiver){
		open(OUT,">$mail_log");
		print OUT "<html> <head>\n";
		print OUT "<meta http-equiv=\"content-type\" content=\"text/html; charset=windows-1252\">\n";
		print OUT "<title>Scan-shipping APAC HRMS - Team colleagues summary report</title></head>\n";
		print OUT "<body>\n";
		print OUT "<p> Hello $list{$manager_id},<br><br>\n";
		print OUT "Below are the leave record summary from your team colleagues :<br><br>\n";
		foreach my $email (sort keys %colleague){
			print OUT "<br><br>---------------------------------------------------------------------------------------------------------------------------------------<br><br>\n";
			if($colleague{$email}->{'office'}){
				print OUT "<i><b>Colleague's name : $colleague{$email}  ($colleague{$email}->{'office'})</i></b><br><br>\n";
			}else{
				print OUT "<i><b>Colleague's name : $colleague{$email}</i></b><br><br>\n";
			}
			print OUT "<b>Job Title : $colleague{$email}->{'jobtitle'}</b><br>\n";
			print OUT "<b>Employment Status : $colleague{$email}->{'empstatus'}</b><br><br>\n";
			print OUT "<table width=\"40\%\" cellspacing=\"1\" cellpadding=\"1\" border=\"1\"><tbody>\n<tr bgcolor=\"#8AB7DF\">\n";
			print OUT "<td valign=\"top\">Total Available days in $year<br></td>\n";
			print OUT "<td valign=\"top\">Used leaves<br></td>\n";
			print OUT "<td valign=\"top\">Leaves balance<br></td>\n";
			print OUT "</tr><tr>\n";
			print OUT "<td valign=\"top\">$colleague{$email}->{'totalleave'}<br></td>\n";
			print OUT "<td valign=\"top\">$colleague{$email}->{'usedleave'}<br></td>\n";
			print OUT "<td valign=\"top\">$colleague{$email}->{'leavebalance'}<br></td>\n";
			print OUT "</tr></tbody></table><br><br>\n";
			if(! $colleague{$email}->{'leaverecords'}){
				print OUT "<br>";
			}else{
				print OUT "<i>Here are all the leave records within year $year :</i><br><br>\n";
				print OUT "<table width=\"62\%\" cellspacing=\"1\" cellpadding=\"1\" border=\"1\"><tbody>\n<tr bgcolor=\"#ffe15f\">\n";
				print OUT "<td valign=\"top\">From<br></td>\n";
				print OUT "<td valign=\"top\">To</td>\n";
				print OUT "<td valign=\"top\">No. of days<br></td>\n";
				print OUT "<td valign=\"top\">Leave type<br></td>\n";
				print OUT "<td valign=\"top\">Apply Status<br></td>\n";
				print OUT "</tr>\n";
				foreach my $line (@{$colleague{$email}->{'leaverecords'}}){
					if($line){
						my @each_record = split(/\|/,$line);
						print OUT "<tr>\n";
						print OUT "<td valign=\"top\">$each_record[0]<br></td>\n";
						print OUT "<td valign=\"top\">$each_record[1]<br></td>\n";
						print OUT "<td valign=\"top\">$each_record[2]<br></td>\n";
						print OUT "<td valign=\"top\">$each_record[3]<br></td>\n";
						if($each_record[4] eq 'Pending for approval'){
							print OUT "<td valign=\"top\">Pending approval (not yet count this in \"Used Leaves\")<br></td>\n";
						}else{
							print OUT "<td valign=\"top\">$each_record[4]<br></td>\n";
						}
						print OUT "</tr>\n";
					}
				}
				print OUT "</tbody></table><br><br>\n";
			}
		}
		print OUT "---------------------------------------------------------------------------------------------------------------------------------------<br><br>\n";
		print OUT "You can find the same information from our HRMS website (<a href=\"https://scshr.ddns.net\">https://scshr.ddns.net</a>).  Any qery, please contact helpdesk\@scan-shipping.com, thanks for your kind attention.<br><br></p>\n";
		print OUT "<div class=\"moz-signature\">Best regards,<p><br>\n";
		print OUT "Scan-shipping APAC HRMS<br>\n";
		print OUT "</p></div></body></html>\n";
		close(OUT);
		system("$mail_command $receiver -s \"HRMS - Team colleagues summary report\" -e \"my_hdr From:Do-not-reply<$sender>\" -e \"my_hdr Content-Type: text/html\" < $mail_log");
		
	}
	unlink($mail_log)if(-f $mail_log);	
}
$dbh->disconnect();
			
			

