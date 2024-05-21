#!/usr/local/sisis-pap/bin/perl



use strict;

use DBI;

### Anpassen! #############
my $server   = "SERVER";
my $database = "DATABASE";
my $user     = "USER";
my $password = "PASSWORD";
$ENV{'SYBASE'} = '/opt/lib/sybase/pkg';
###########################

my $dbh = DBI->connect("dbi:Sybase:server=$server;database=$database", $user, $password,
        { PrintError => 0,
          RaiseError => 1
        }) or die "connect: $DBI::errstr\n";


#use lib '/usr/local/sisis-pap/lib';
#use ubmsis;
#use feature "say";
###JB# use lib "/usr/local/sisis-pap/perl5.16.2/lib/site_perl/5.16.2/sun4-solaris-thread-multi/auto/DBD/syb150/DBD";
# Debugging -> keine Logdatei!
my $DEBUG = 0;

# Parameter lesen
my $drucker = $ARGV[0];
my $file    = $ARGV[1];
$DEBUG = 1 if $ARGV[2] and $ARGV[2] eq "-d";

# aktuelles Datum/Uhrzeit
my @ulocaltime = localtime(time);
++$ulocaltime[4];
$ulocaltime[5] += 1900;
my $udate   = sprintf "%02d.%02d.%d", @ulocaltime[3,4,5];
my $datestamp  = sprintf "%04d.%02d.%02d", @ulocaltime[5,4,3];

# Log konfigurieren
my $logmsg  = sprintf "%02d.%02d.%d %02d:%02d:%02d\n", @ulocaltime[3,4,5,2,1,0];
$logmsg .= "Drucker: $drucker\n";
$logmsg .= "Datei  : $file\n";
my $logfile = "/home/var/spool/sisis/avserver.ubmsis/batch/tmp/print-magzet.log";
#my $logfile = "/home/sisis/almut/print-magzet.log";
my $printerlog = "/home/ubmsisis/bilgram/printlog";
my $sleepSeconds = 1;  # Anzahl Sekunden, die zwischen den Ausdrucken gewartet werden soll (kann auch 0.5 etc. sein); Konfigurierbar auch in Druckerkonfiguraiton

# Datei mit Barcode-Softfont, Druckbefehl
my $bcfontdatei = "/home/ubmsisis/druck/pcl/code39e.sfp";
my $druckcom    = "| /usr/local/sisis-pap/cups/bin/lpr -o raw -P $drucker";
###my $druckcom    = "| /usr/local/sisis-pap/cups/bin/lpr -o raw -h -P $drucker";
#$druckcom       = "| cat -";

# Parameter prüfen
unless ( $drucker and $file ) {
  &mydie("Falsche Anzahl Parameter!");
}
unless (-r $ARGV[1]) {
  &mydie("Datei $ARGV[1] nicht lesbar!");
}

# Druckerkonfiguration
# Tabelle: Druckername -> [ Druckertyp, Name verschlüsseln (0/1/2), Druckverzögerung in Sekunden (kann auch 0.5 etc. sein) ]
# Verschleierung:
# 1 Muster: ABC_1234
# 2 Muster: A 12.345
# ANPASSEN
my %druconf = ("bvb_dr1"  =>  ["hp4300",    1, 1],
               "bvb_dr2"  =>  ["hp2100",    1, 1],
               "ubmldruck1"  =>  ["4827",    1, 1],
               "ubmldruck2"  =>  ["4827",    1, 1],
               "ubmldruck3"  =>  ["4827",    1, 1],
               "ubmdruck1"  =>  ["4827",    1, 1],
               "ubmdruck2"  =>  ["4827",    1, 1],
               "ubmdruck3"  =>  ["4827",    1, 1],
               "ubmdruck4"  =>  ["4827",    1, 1],
               "ubmdruck5"  =>  ["4827",    1, 1],
               "ubmdruck6"  =>  ["4827",    1, 1],
               "ubmdruck7"  =>  ["4827",    1, 1],
               "ubmdruck9"  =>  ["4827",    1, 1],
               "ubmdruck10" =>  ["4827",    1, 1],
               "ubmdruck11"  =>  ["hp2100",    1, 1],
               "ubmdruck12"  =>  ["hp2100",    1, 1],
               "ubmdruck13"  =>  ["hp2100",    1, 1],
               "ubmdruck15"  =>  ["4827",    1, 1],
               "ubmdruck16"  =>  ["hp2100",    1, 1],
               "ubmdruck17"  =>  ["hp2100",    1, 1],
               "ubmdruck18"  =>  ["hp2100",    1, 1],
               "ubmdruck20"  =>  ["hp2100",    1, 1],
               "ubmdruck21"  =>  ["4827",    1, 1],
               "ubmdruck22"  =>  ["4827",    1, 1],
               "ubmdruck23"  =>  ["4827",    1, 1],
               "ubmdruck25"  =>  ["hp2100",    1, 1],
               "ubmdruck51"  =>  ["hp2100",    1, 1],
               "ubmdruck52"  =>  ["hp2100",    1, 1],
               "ubmdruck53"  =>  ["hp2100",    1, 1],
               "ubmdruck54"  =>  ["hp2100",    1, 1],
               "ubmdruck55"  =>  ["hp2100",    1, 1],
               "ubmdruck56"  =>  ["hp2100",    1, 1],
               "testl7"  =>  ["4827",    1, 1],
              );
# Drucker definiert?
unless ($druconf{$drucker}) {
  &mydie("Drucker $drucker ist nicht definiert!");
}


# PCL-Sequenzen
my ($reset, $psize, $tray, $linef, $sset, $perf);
my ($font, $fontb, $fontbig, $fontvbig, $fontsm);
my ($bcsoft, $bcein, $bcaus);
my ($pos_s, $pos_k, $pos_b, $hpos_bc, $pos_n, $hpos_d, $line, $pos_ben, $hpos_ben, $vpos_d);
&config($druconf{$drucker}->[0]);

# Zweigstellen-Sigel-Zuordnung
my %sigel = ("00" => "19",
            );

# Bestellzettel-Datei einlesen
my $best    = `cat $file 2>/dev/null`;
&mydie("Bestelldatei enthält keinen Text!") unless $best;

# Inhalt Logdatei
$logmsg .= "$best\n" if $best;                             # Bestelltext in Log-Datei
$logmsg =~ s/^\*\*.+?\*\*$//gm;                            # Sternzeilen und
$logmsg =~ s/\e\[1;4;001 z\e\#;\*TEMP\d+\*\e\#;//g;        # Temp-Mediennummer als Barcode weg
$logmsg =~ s/[\r\n\f ]+$/\n/gs;                            # überflüssige Leerzeichen entfernen;
$logmsg =~ s/^\-\-\-+\n\n//gm;                             # Trennlinie in Bestellung weg

# Dateiname ohne Pfad für Ausdruck
$file =~ s/^.+\///g;

# Daten aus Bestellzettel holen
my ($btype, $bdate, $btime, $term, $zwst, $zwstn, $benunum, $benunam, $signa, $gsi, $ausg, $verfa, $titel);
($btype)   = $best =~ /^ *([A-Z] [A-Z] [A-Z] .+)$/m;       # Art der Bestellung (M A G A Z I N   -  B E S T E L L U N G)
($bdate)   = $best =~ /^Vom:\s+([\d\.]+)/m;                # Bestelldatum
($btime)   = $best =~ /([\d\:]+\s+Uhr)$/m;                 # Bestellzeit
($term)    = $best =~ /Terminal:\s+(.+?) /m;               # Terminal
($zwstn)   = $best =~ /Zweigst:\s+(\d+)/;                  # Zweigstellennummer
($zwst)    = $best =~ /^Name Zweigstelle\s+\:\s+(.+)$/m;   # Zweigstelle
($benunum) = $best =~ /^Benutzernummer\s+\:\s+(\d+) /m;    # Benutzernummer
($benunam) = $best =~ /^(?:Name|Bezeichnung)\s+\:\s+(.+?)\s*$/m; # Name/Bezeichnung Benutzer
($signa)   = $best =~ /^Signatur\s+\:\s+(.+?)\s*$/m;       # Signatur
($gsi)     = $best =~ /^Mediennummer\s+\:\s+(.+?)\s*$/m;   # Mediennummer
($ausg)    = $best =~ /^Ausgabeort\s+\:\s+(.+?)\s*$/m;     # Ausgabeort
($verfa)   = $best =~ /^Verfasser\s+\:\s+(.+?)\s*$/m;     # Ausgabeort
($titel)   = $best =~ /^Titel\s+\:\s+(.+?)\s*$/m;     # Ausgabeort
my $benunamo = my $benunamu = $benunam;
my $bereit = substr( $benunum, -5, 2 );					# Bereitstellungsnummer

# Sigel aus d02ben und d02zus holen bei Bestellzetteln fremder Bibliotheken
my ($erg, $aufart, $fremdnr);
###unless ($best =~ /S O F O R T A U F R U F/) {
###  $erg = $dbh->selectall_arrayref("select d02ben.d02aufart, d02zus.d02fremd_nr ".
###    "from d02ben,d02zus where d02ben.d02bnr = '$benunum' and d02ben.d02bnr = d02zus.d02z_bnr");
###  ($aufart,$fremdnr) = @{$erg->[0]};                    # Aufnahmeart und Sigel aus d02ben/d02zus
###}
###$fremdnr = "" unless $aufart == 2;
###$dbh->disconnect;

# Bestellzettel verändern
$best  =~ s/$btype//g;                                     # Bezeichnung Bestellart aus Bestellzettel löschen
$btype =~ s/ //g;                                          #  und Leerzeichen daraus entfernen ;
$best  =~ s/\e\[1;4;001 z\e\#;\*TEMP\d+\*\e\#;//g;         # Temp-Mediennummer als Barcode weg
$best  =~ s/^\*\*.+?\*\*$//gm;                             # Sternzeilen und
$best  =~ s/^[\r\n ]+(.+?)[\r\n\f ]+$/ $1/gs;              # überflüssige Leerzeichen entfernen;

+

# Mediennummer und AFL-Nummer als Barcode
$best  =~ s/^(Mediennummer\s+\:\s+)(.+?)\s*$/\n$1$2$hpos_bc$bcein$2$bcaus$fontb/m;
# AFL-Nummer ohne @
$best  =~ s/^(AFL-Nummer\s+\:\s+)([^\@].+?)\s*$/$1$2$hpos_bc${bcein}$2$bcaus$font/m;
# AFL-Nummer mit @
$best  =~ s/^(AFL-Nummer\s+\:\s+)\@(.+?)\s*$/$1\@$2$hpos_bc${bcein}F$2$bcaus$font/m;
$best  =~ s/^(.+)(AFL-Nummer.+?\n)(.+)$/$1$3\n\n$2/s;
# Benutzernummer als Barcode
#$best  =~ s/^( Benutzernummer\s+\:\s+)(.+?)\s*$/\n$1$2\n\n$hpos_bc$bcein$2$bcaus$fontb/m;

# Name und Benutzernummer verschleiern?
# Benutzergruppen, bei denen persönliche Angaben nicht verschleiert werden sollen
my %nichtVerschleiern = (66 => 1,
			 75 => 1,
                         80 => 1,
                        );
my %fernleih = (75 => 1,
		80 => 1,
		);

if ( $druconf{$drucker}->[2] > 0 ) {
  my $benunumQ = $dbh->quote( $benunum );
  my $bg = 1;
  unless ($best =~ /S O F O R T A U F R U F/) {
    my $erg = $dbh->selectall_arrayref("select d02bg from d02ben where d02bnr = $benunumQ");
    $bg = $erg->[0]->[0];                                 # Benutzergruppe ermitteln
  }
  unless ( $nichtVerschleiern{ $bg } ) {
    $best =~ s/^ \*.+\*.$/" "."*"x80/em;
    $best =~ s/^ (?:Name|Bezeichnung)\s+\:\s+.+\n//m;        # Name/Bezeichnung Benutzer aus Text entfernen
    $best =~ s/^ Benutzernummer\s+\:\s+\d+.+\n//m;           # Benutzernummer aus Text entfernen
    my $nameKurz = $benunam;
    $nameKurz =~ s/[^0-9A-Za-zÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ]//g;  # alle Sonder/Leerzeichen weg

    if ( $druconf{$drucker}->[1] == 1 ) {
      # Muster: ABC_1234
      #$benunamo = $benunum;							# oben kein Name, stattdessen Benutzernummer
      $benunamo = "";								# oben kein Name und keine Benutzernummer
      $nameKurz = sprintf( "%-4s", substr( $nameKurz, 0, 3 ) );			# kürzen auf drei Zeichen + Leerzeichen
      $nameKurz =~ s/ /_/g;							# Leerzeichen durch Unterstrich ersetzen
      my $numKurz = substr( $benunum, -4 );					# letzte vier Stellen Benutzernummer
      $benunamu = "$nameKurz$numKurz";						# unten Name/Benutzernummer gekürzt
      $benunum = "";								# unten keine Benutzernummer
    }
    if ( $druconf{$drucker}->[1] == 2 ) {
      # Muster: A 12.345
      #$benunamo = $benunum;							# oben kein Name, stattdessen Benutzernummer
      #$benunamo = "";								# oben kein Name und keine Benutzernummer
      $nameKurz = sprintf( "%-2s", substr( $nameKurz, 0, 1 ) );			# kürzen auf ein Zeichen + Leerzeichen
      my $numKurz = substr( $benunum, -5 );					# letzte 5 Stellen Benutzernummer
      $numKurz =~ s/(..)(...)/$1.$2/;						# Punkt zwischen 2 und 3. Stelle
      $benunamo = "$nameKurz$numKurz";						# oben Name/Benutzernummer gekürzt
      $benunamu = "$nameKurz$numKurz";						# unten Name/Benutzernummer gekürzt
      $benunum = "";								# unten keine Benutzernummer
    }
  }
}

$dbh->disconnect;

# Druckdaten zusammensetzen
my $prn = "$reset$psize$tray$linef$sset$perf";					# Drucker initialisieren
$prn .= $bcsoft;								# Barcode-Softfont
#$prn .= "$pos_s$fontb$benunamo$hpos_d$fontbig$fremdnr\n\n";			# Benutzername oben (ggf. mit Sigel)
$prn .= "$fontvbig$signa\n";							# Signatur
$prn .= "$fontvbig$line\n";							# Linie
$prn .= "$hpos_d$fontsm$file";							# Dateiname
$prn .= "$pos_k$fontbig$btype\n";						# Art der Bestellung
#$prn .= "${fontb} vom $bdate $btime\n";					# Datum der Bestellung
#$prn .= "${fontb} Zweigstelle: $zwstn / $zwst";				# Zweigstelle
$prn .= $sigel{$zwstn} ? "${hpos_bc}Sigel:$fontbig $sigel{$zwstn}\n" : "\n";	# Sigel, falls definiert
#$prn .= "${fontb} Terminal: $term";						# Terminal-Name
$prn .= "${fontb}\n";						# Terminal-Name
$prn .= "Vom: $bdate    Terminal: $term   Zweigst: $zwstn   $btime\n";
$prn .= "Name Zweigstelle : $zwst\n";
$prn .= "Benutzer  : $benunamu\n";
$prn .= "\nFolgendes Medium wird benötigt:\n--------------------------------------------------------------------------------\n\n";
$prn .= "Verfasser   : $verfa\n";
$prn .= "Titel          : $titel\n\n";
$prn .= "Mediennummer : $gsi   $bcein$gsi$bcaus\n$fontb";
$prn .= "Signatur          : $signa\n";
$prn .= "Ausgabeort       : $ausg\n";
$prn .= "$fontvbig\n\n\n\n\n\n";

if (defined $fernleih{$bg} ) { $prn .= "A\nFernleihbib: $benunamu\n"; }
# $prn .= "A\nFernleihbib: $benunamu\n" if ( $fernleih{ $bg } );

$prn .= "\n$signa\n\n$ausg\n\n> $bereit <  $benunamu";
#$prn .= "$pos_b$fontb$best";							# Originaltext der Bestellung
$prn .= "$pos_n$fontvbig$line";							# Linie
#$prn .= "$fontb\n\n";								# 2 Leerzeilen
$prn .= "$fontb";								# 2 Leerzeilen
#$prn .= "$bcsoft$benunum$hpos_bc$bcein$benunum$bcaus" if $benunum;			# Benutzernummer
###JB $prn .= "$pos_ben\n\n${fontb} Benutzernummer: $fontb$benunumo$hpos_ben$bcein$benunum$bcaus";  # Benutzernummer mit Barcode oberhalb der Fußzeile
$prn .= "$vpos_d$fontb$hpos_d$udate\n\n";					# aktuelles Datum
#$prn .= "$fontvbig$benunamu";							# Name des Bestellers
$prn .= $reset;

# zum Drucker
open D, $druckcom or &mydie("Magazinzettel-Druck-Abbruch bei <open lp>:\n$!");
print D $prn;
close D or &mydie("Magazinzettel-Druck-Abbruch bei <close lp>: $!");

# Logdatei schreiben
&log;


###########################################################################

sub mydie {
  # Abbruch, Fehlerausgabe in Log-Datei
  my $msg = shift;
  &log("Abbruch: $msg");
  exit 1;
}

sub log {
  # Log-Datei schreiben
  my $logline = "+"x79;
  $logmsg .= "\n$_[0]" if $_[0];                           # Messages von "mydie" übergeben?

  if ( $DEBUG ) {
    print "$logmsg\n$logline\n\n";
  } else {
    open L, ">>$logfile" or die;
    print L "$logmsg\n$logline\n\n";
    close L;
    # Drucker-Logdatei schreiben
    open L, ">>$printerlog/$drucker-$datestamp" or die;
    print L "$logmsg\n$logline\n\n";
    close L;
  }
}

###JB  open L, ">>$logfile" or die;
###JB  print L "$logmsg\n$logline\n\n";
###JB  close L;
###JB }

sub config {
  # Drucker konfigurieren
  my $drutyp = shift;

  # Voreinstellungen
  $reset    = "\eE\e&l1E";                                 # Reset
  $psize    = "\e&l25A";                                   # Papierformat A5
  $tray     = "";                                          # Papierschacht
  $linef    = "\e&k2G";                                    # Zeilenende: LF = CR+LF
  $sset     = "\e(0N";                                     # Zeichensatz Latin 1
  $perf     = "\e&l0L";                                    # kein Perforationssprung

  $font     = "\e(0N\e(s0p16h0s3b4102T";                   # LGothik 20cpi bold
  $fontb    = "\e(0N\e(s1p10v0s3b4148T";                   # Univers 10pt bold
  $fontbig  = "\e(0N\e(s1p14v0s3b4148T";                   # Univers 14pt bold
  $fontvbig = "\e(0N\e(s1p18v0s3b4148T";                   # Univers 20pt bold
  $fontsm   = "\e(0N\e(s1p7v0s0b4148T";                    # Univers 8pt

  $bcsoft   = "\e*c1D" .                                   # Font-ID
              `cat $bcfontdatei` .			   # Soft-Font
              "\e*c5F";                                    # Permanent 5; Temporär 4
  $bcein    = "\e(9U\e(s1p12.5v0s0b254T*";                 # Barcode einschalten
  $bcaus    = "*\e(0N";                                    # Barcode ausschalten

  $pos_s    = "\e*p0x00Y";                                 # Position Signatur
  $pos_k    = "\e*p0x300Y";                                # Position Kopf
  $pos_b    = "\e*p0x530Y";                                # Position Original-Bestellung
  $hpos_bc  = "\e*p850X";                                  # horiz. Position Barcode
  $pos_n    = "\e*p0x2250Y";                               # Position Fußzeile
  $pos_ben  = "\e*p0x2100Y";				   #  vertikale Position Benutzernummer als Barcode	
  $hpos_ben = "\e*p850X"; 				   # horizontale Position Benutzernumnmer als Barcode	
  #$hpos_d   = "\e*p1375X";                                # horiz. Position Datum (rechtsbuendig)
  $hpos_d   = "\e*p0X";                                    # horiz. Position Datum (linksbuendig)
  $line     = $fontvbig . ("_"x44);                        # Linie
  $vpos_d   = "\e*p0x2250Y";				   # vertikale Position Datum

  # Druckerspezifische Einstellungen
  if ($drutyp eq "hp2100") {                               #HP LJ 2100/2200
    $psize  = "\e&l26A";                                   # Papierformat A4
    $tray   = "\e&l1H";                                    # Papierschacht
    $pos_n  = "\e*p0x3050Y";                               # Position Fußzeile
  }
}

__END__;
