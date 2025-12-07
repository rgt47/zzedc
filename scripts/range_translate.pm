# range_translate.pm
# author: Mei Qiu
# link to wiki:
# modified: 06/24/09
# remove [[]-] syntax (version 136: backup before removing [[]-] syntax)
# added [:] syntax
# added notbetween
# added notin
# modified: 07/01/09
# modified named parameters replace 'param'=>value to param=value
# handle special expression ---- c, n, m
# system default to notin(n) when rangeval is empty, except when visible is off
# if exists [] statement then append 1; in the end of rangeval
# check error []some code[] without grouping
# modified: 08/03/09 (version 281: backup before this change)
# system default (when field is visible): if code is defined, allow c,m only, else use notin(n)
# modified: 08/17/09
# assumption change: allow n for type T text or paragraphs all the time; check for field dependency; add more specific error messages
# if log form, and recno < 0 then allow x to be n
# if code like 1..9, and field contains decimal places, use between ... and ... instead of in statement
# modified: 08/30/2009
# added new feature "subquestion_trigger"(layout)
# added new logic for binary checkbox groups
# fixed bug
# version 415: 09/09/2009
# subquestion force null
# modified error messages
# modified: 09/18/2009
# allow one option check box and radio button to always allow true
# modified: 09/28/2009 backup version 450, fix bug for subquestion_trigger=(fld:n,m) when fld is a checkbox group
# subquestion_trigger does not require indent to be declared in the layout anymore
# for numeric text input box, if code is defined, check range on code
# 10/05/09 allow more compicated code syntax, n1..n2[:step],  e.g. 1..2:0.5, 5, 99, 0.8, 200..300:15
# 10/08/09 add "letpass" in the layout to set the range check to true, and letpass should not overwrite what's manually put in the rangeval
# 10/14/09 add "+" in subquestion_trigger for and relation between each () group
# 10/16/09 fix bug: &notin, function() param not properly translated due to $function_flag--
# 10/30/09 fix bug: sub get_dependent_field
# 12/01/09 add new feature to letpass, allow letpass to define a date, e.g. letpass=09/01/2008
#			if date is defined, allow rangeval to always pass when user date is before or equal to that date
# latest working version 722

## the following is no longer implemented, check notes on 1/07/10 instead
# 12/09/09 add new feature in layout, if layout contains wspost(type) e.g. wspost(adas)
#			rangeval will translate this into syntax and add it to the top of the checks:
# 					e.g. 	WS=|ws|adas|ws|; if WS='1' then true else return(WS) endif
#			rangeprl will be translated to the following:
#					e.g.  	my $_WS;
#							$_WS=wspost(url=>'/tools/rc/adas', params=>\%vals);
#							if($_WS eq '1'){
#								1;
#							}
#							else{return($_WS);
#							}
#					which the url is hard coded based on the type passed to the ws() function
#					adas => '/tools/rc/adas'
## the above is no longer implemented, check notes on 1/07/10 instead

# 1/07/10 add new feature in layout, if layout contains calc_i(adas_igiv.bw, ADTOTAL, K1:Q1TOT|K2:Q2TOT(optional)) -> insert
#														calc(adas_igiv.bw, COMPAREFIELD2(optional), K1:Q1TOT|K2:Q2TOT(optional)) -> compare
#			rangeval will translate this into syntax and add it to the top of the checks:
# 					e.g. 	WS=|wspost|; if WS='1' then true else return(WS) endif
#			rangeprl will be translated to the following:
#					e.g.  	my $_WS;
#							$_WS=wspost(url=>'/tools/rc/adcs_igiv.bw', mode=>'i', alias=>'K1:Q1TOT|K2:Q2TOT', dest=>'ADASTOT',  params=>\%vals);
#							if($_WS eq '1'){
#								1;
#							}
#							else{
#								return($_WS);
#							}
# mode: i (insert), c(compare)
# Gus's wrapper function for wspost:returns 1 or error message
# note: set_track takes named parameter: track, global
# 4/6/10: if layout contains "password", validates password
# 6/14/2010: in get_subquestion_trigger function, rewrite the logic if main question is a checkbox group, type 'K'
# 6/14/2010: if calc_i, then only return the result of calc_i, and not checking any other default range checks, e.g. allow n for x
# 6/23/2010: add more error message when value x is out of range
# 7/13/2010: when layout contains keyword "time_military", and ftype is "T" call time_validate() function
# 9/23/2010: allow cross project sql query in q3 syntax table{},
#           use __ (double underscores) as delimitor between project name and table name
#			e.g. registry{};  will take the current project's registry table
#                admin__medlist{}; will take the admin project's medlist table
# 12/15/2010: bug fix when indent=1 or subquestion_trigger is defined, and time_military[_strict] is also defined in layout
# 3/3/2011: bug fix, time_military and time_military_restrict didn't encounter the visibleval, move visibleval logic to a higher precedence
# 3/29/2011: bug fix, if calc_i, then should do nothing, and should not handle the visibility cases either
# 5/3/2011: bug fix, time_military_strict not encountering log form case when recno==-4
# 7/13/2011: support n1..n1[:steper] in the subquestion trigger syntax
# 7/22/2013: add missing_trigger feature

package tools::range_translate;
require Exporter;

use strict;
use Data::Dumper;

our @ISA    = qw(Exporter);
our @EXPORT = qw(translate_rangecode translate_rangecode_doc);

sub sendEmail
{
    my ( $to, $from, $subject, $message ) = @_;
    my $sendmail = '/usr/lib/sendmail';
    open( MAIL, "|$sendmail -oi -t" );
    print MAIL "From: $from\n";
    print MAIL "To: $to\n";
    print MAIL "Subject: $subject\n\n";
    print MAIL "$message\n";
    close(MAIL);
}

sub trim
{
    my $s = shift;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

#--------------------- sub gathering meta data ---------------------#
sub generate_datadic_info
{
    my $prot         = lc shift;
    my $dbo          = shift;
    my $datadic_info = shift;
    my %datadic_info = %{$datadic_info};
    my $debug        = shift;

    if ( !$prot )
    {
        return ( { error => '400', msg => qq{missing prot parameter} } );
    }
    if ( !$dbo->{db} )
    {
        return ( { error => '400', msg => 'missing dbo->{db} parameter' } );
    }
    if ( !$dbo->{dbh} )
    {
        return ( { error => '400', msg => 'missing dbo->{dbh} parameter' } );
    }

    my @meta_fields =
        qw(trim(tblname) trim(fldname) trim(type) trim(ftype) trim(code));
    my $str_fields = join ",", @meta_fields;

    # query information from datadic table
    my $str =
        qq{select $str_fields from $prot\_datadic order by tblname, colid};
    my $str2 = $dbo->{db}->translate_sql($str);
    my $sth  = $dbo->{dbh}->prepare($str2)
        or warn "Couldn't prepare $str statement!\n";
    my $rv = $sth->execute or warn "Couldn't execute $str statement!\n";

    while ( my ( $tblname, $fldname, $type, $ftype, $code ) =
        $sth->fetchrow_array )
    {

        # gather table type, and indexes information
        if ( lc $fldname eq 'id' )
        {

            # assign table types
            $datadic_info{$prot}{ lc $tblname }{ftype} = $ftype;

# retrieve indexes information from "code" field, e.g. "crfname","ADAS-Cognitive Behavior (AD)","indexes","dha_adas_idx=RID,VISCODE,ENTRY","notnullcols","ID,RID,SITEID,VISCODE,ENTRY,USERID,USERDATE"
            my @temp_array = split ";", ( split '\",\"', $code )[3];
            my $index_str = ( join ";", @temp_array );
            $index_str =~ /(_idx=)([^;]*)[;]?/;
            my @indexes;
            @indexes = split ",", $2 if ($1);
            map {
                $datadic_info{$prot}{ lc $tblname }{'indexes'}{ lc $_ } =
                    1
            } (@indexes);

            # skip entry information from table indexes
            delete $datadic_info{$prot}{ lc $tblname }{'indexes'}{'entry'}
                if (
                $datadic_info{$prot}{ lc $tblname }{'indexes'}{'entry'} );

# skip recno information from table indexes, asking user to specific recno information
            delete $datadic_info{$prot}{ lc $tblname }{'indexes'}{'recno'}
                if (
                $datadic_info{$prot}{ lc $tblname }{'indexes'}{'recno'} );
        }

        # gather field type information
        $datadic_info{$prot}{ lc $tblname }{field}{ lc $fldname }{type} =
            lc $type;
    }
    print Dumper( \%datadic_info ), "\n" if ( $debug == 1 );
    return \%datadic_info;
}

# sub function translate code option to a string
sub get_code_option
{
    my $prot  = lc shift;
    my $dbo   = shift;
    my $tbl   = uc shift;
    my $fld   = uc shift;
    my $debug = shift;

    # remove all white space for tablename and fieldname
    $tbl =~ s/^\s+//;
    $tbl =~ s/\s+$//;
    $fld =~ s/^\s+//;
    $fld =~ s/\s+$//;

    my @res;

    # no need to query if no table or fieldname is defined
    if ( !$tbl || !$fld )
    {
        return \@res;
    }

    # query code
    # query information from datadic table
    my $str =
        qq{select code from $prot\_datadic where tblname=\'$tbl\' and fldname=\'$fld\' and ftype not in('S') order by tblname, colid};

#	my $str  = qq{select code from cctg589_datadic where tblname=\'INCLEXCL\' and fldname=\'SEHGHUSE\' order by tblname, colid};
    my $str2 = $dbo->{db}->translate_sql($str);
    my $sth  = $dbo->{dbh}->prepare($str2)
        or warn "Couldn't prepare $str statement!\n";
    my $rv = $sth->execute or warn "Couldn't execute $str statement!\n";

    my $code = $sth->fetchrow_array;
    if ( $code !~ /^\s*select/ )
    {
        my @temp = split ";", $code;
        foreach my $a (@temp)
        {
            next if ( length($a) == 0 || $a =~ /^\s+$/ );
            my @temp2 = split "=", $a;
            push @res, $temp2[0] if ( length( $temp2[0] ) > 0 );
        }
    }
    return \@res;
}

sub get_dependent_field
{
    my $prot   = lc shift;
    my $dbo    = shift;
    my $tbl    = uc shift;
    my $fld    = uc shift;
    my $indent = shift;
    my $debug  = shift;

    # remove all white space for tablename and fieldname
    $tbl =~ s/^\s+//;
    $tbl =~ s/\s+$//;
    $fld =~ s/^\s+//;
    $fld =~ s/\s+$//;

    # query colid for this field
    # query information from datadic table
    my $str =
        qq{select colid from $prot\_datadic where tblname=\'$tbl\' and fldname=\'$fld\' limit 1};
    my $str2 = $dbo->{db}->translate_sql($str);
    my $sth  = $dbo->{dbh}->prepare($str2)
        or warn "Couldn't prepare $str statement!\n";
    my $rv = $sth->execute or warn "Couldn't execute $str statement!\n";

    my $colid = $sth->fetchrow_array;
    if ( $indent == 1 )
    {
        $str =
            qq{select fldname from $prot\_datadic where tblname=\'$tbl\' and (layout is null or layout not like \'%indent%\') and colid<$colid order by colid desc limit 1};
    }
    else
    {
        $indent--;
        $str =
            qq{select fldname from $prot\_datadic where tblname=\'$tbl\' and (layout is null or layout like \'%indent%=%$indent%\') and colid<$colid order by colid desc limit 1};
    }
    my $str2 = $dbo->{db}->translate_sql($str);
    my $sth  = $dbo->{dbh}->prepare($str2)
        or warn "Couldn't prepare $str statement!\n";
    my $rv = $sth->execute or warn "Couldn't execute $str statement!\n";

    my $res = $sth->fetchrow_array;
    return $res;

}

# funtion returns a reference to an array of two hashes
# 1st hash: key with fld from the table that belongs to the binary checkboxes, and value all set to 1
# 		it will be usded to determine whether a field is belong to a binary checkbox group
# 2nd hash: key with last fld from each binary checkbox group found in the table, value will be an array lists
# 		fldnames for each binary checkbox group
sub get_binarycheckbox_info
{
    my $prot  = lc shift;
    my $dbo   = shift;
    my $tbl   = uc shift;
    my $debug = shift;

    # remove all white space for tablename
    $tbl =~ s/^\s+//;
    $tbl =~ s/\s+$//;

    my @result;
    my %is_binarychk_hash;
    my %binarychk_info;
    my @temp_array;
    if ( $prot && $tbl )
    {

        # query information from datadic table
        my $str =
            qq{select count(id) from $prot\_datadic where tblname='$tbl' and layout like '%checkrange\_start%'};
        my $str2 = $dbo->{db}->translate_sql($str);
        my $sth  = $dbo->{dbh}->prepare($str2)
            or warn "Couldn't prepare $str statement!\n";
        my $rv = $sth->execute or warn "Couldn't execute $str statement!\n";
        my $count = $sth->fetchrow_array;
        if ( $count > 0 )
        {
            $str =
                qq{select fldname, layout from $prot\_datadic where tblname='$tbl' order by colid};
            $str2 = $dbo->{db}->translate_sql($str);
            $sth  = $dbo->{dbh}->prepare($str2)
                or warn "Couldn't prepare $str statement!\n";
            $rv = $sth->execute or warn "Couldn't execute $str statement!\n";

            my $binarychk_flag = 0;

            # gather binary checkbox information
            while ( my ( $fldname, $layout ) = $sth->fetchrow_array )
            {

                # remove all white space for tablename and fieldname
                $fldname =~ s/^\s+//;
                $fldname =~ s/\s+$//;
                if ( $layout =~ /checkrange\_start/i )
                {
                    $binarychk_flag = 1;
                    @temp_array     = ();
                    push @temp_array, lc($fldname);
                }
                elsif ( $layout =~ /checkrange\_end/i )
                {
                    $binarychk_flag = 0;
                    push @temp_array, lc($fldname);
                    $binarychk_info{ lc($fldname) } = [@temp_array];
                }
                else
                {
                    next unless ($binarychk_flag);
                    push @temp_array, lc($fldname);
                }
                $is_binarychk_hash{ lc($fldname) } = 1;
            }
            print Dumper( \%is_binarychk_hash ) if ($debug);
            print Dumper( \%binarychk_info )    if ($debug);

            $result[0] = \%is_binarychk_hash;
            $result[1] = \%binarychk_info;
        }
    }
    return \@result;
}

# parameter: subquestion layout, %is_checkbox_hash reference
# return: reference to an array of two elements
# 1st element: string of rangeval check assume mainquestion is positive
# 1st element: string of rangeval check assume mainquestion is negative
sub get_subquestion_trigger
{
    my $layout      = shift;
    my $ischeck     = shift;
    my %is_checkbox = %{$ischeck};
    my @result;
    my @array1;
    my @array2;

    my @temp = split ';', $layout;

    # join: 1=or relation (default), 2=and relation
    my $join = 1;
    foreach my $l (@temp)
    {
        if ( $l =~ /subquestion\_trigger\s*=\s*\((.*)\)/i )
        {
            my $temp = $1;
            my @condition;

# note, subquestion_trigger is assumed to contain either all "or" relation or all "and" relation
            if ( $temp =~ /\)\+\(/ )
            {
                @condition = split( /\)\+\(/, $temp );
                $join = 2;
            }
            else
            {
                @condition = split( /\)\(/, $temp );
            }

            foreach my $c (@condition)
            {
                my $in_cond;
                my $notin_cond;
                next if ( $c =~ /^\s+$/ || length($c) == 0 );
                my @temp2 = split ':', $c;
                my $size_temp2 = @temp2;

                # check if main question $temp2[0] is a check box group
                $temp2[0] =~ s/^\s+//;
                $temp2[0] =~ s/\s+$//;

# added by mei 07/13/2011: support n1..n2[:steper] in the subquestion_trigger syntax
                my $values = $temp2[1];
                if ( $size_temp2 > 2 )
                {
                    foreach my $vindex ( 2 .. $size_temp2 - 1 )
                    {
                        $values = $values . ":" . $temp2[$vindex];
                    }
                }

                if ( !exists $is_checkbox{ lc( $temp2[0] ) } )
                {
                    push @array1, $temp2[0] . qq{ in(} . $values . qq{)};
                    push @array2, $temp2[0] . qq{ notin(} . $values . qq{)};
                }
                else
                {

                    # handle check box group
                    my @temp3 = split ',', $temp2[1];
                    if ( $temp2[1] !~ /\b(n|m)\b/ )
                    {
                        $in_cond    = $temp2[0] . qq{ in(n,m)};
                        $notin_cond = $temp2[0] . qq{ notin(n,m)};
                    }
                    elsif ( $temp2[1] !~ /\b(n)\b/ && $temp2[1] =~ /\b(m)\b/ )
                    {
                        $in_cond    = $temp2[0] . qq{ in(n)};
                        $notin_cond = $temp2[0] . qq{ notin(n)};
                    }
                    elsif ( $temp2[1] =~ /\b(n)\b/ && $temp2[1] !~ /\b(m)\b/ )
                    {
                        $in_cond    = $temp2[0] . qq{ in(m)};
                        $notin_cond = $temp2[0] . qq{ notin(m)};
                    }

# array5: or relation for values belongs to a main question is checkbox. e.g. in adverse form: (saereason:1,2)
                    my @array5;
                    my @array6;
                    foreach my $c2 (@temp3)
                    {
                        $c2 =~ s/^\s+//;
                        $c2 =~ s/\s+$//;
                        if ( $c2 !~ /\d+\.\.\d+/ )
                        {
                            push @array5,
                                qq{ index(} . $temp2[0] . qq{,$c2)>-1};
                            push @array6,
                                qq{ index(} . $temp2[0] . qq{,$c2)=-1};
                        }
                        else
                        {
                            $c2 =~ /(\d+)\.\.(\d+)/;
                            for ( my $count = $1; $count < $2; $count++ )
                            {
                                push @array5,
                                    qq{ index(} . $temp2[0] . qq{,$count)>-1};
                                push @array6,
                                    qq{ index(} . $temp2[0] . qq{,$count)=-1};
                            }
                        }
                    }
                    my $flat_array5 = join ' or ',  @array5;
                    my $flat_array6 = join ' and ', @array6;
                    $flat_array5 = qq{(} . $flat_array5 . qq{)};
                    $flat_array5 = qq{$notin_cond and } . $flat_array5
                        if $notin_cond;
                    $flat_array6 = qq{($in_cond or } . $flat_array6 . qq{)}
                        if $in_cond;
                    push @array1, $flat_array5;
                    push @array2, $flat_array6;
                }
            }
            if ( @array1 && @array2 )
            {
                if ( $join == 2 )
                {

                    # and relation  subquestion_trigger=()+()+()
                    $result[0] = join ' and ', @array1;
                    $result[1] = join ' or ',  @array2;
                }
                else
                {

                    # or relation subquestion_trigger=()()()
                    $result[0] = join ' or ',  @array1;
                    $result[1] = join ' and ', @array2;
                }
            }

        }
    }
    return \@result;
}

# parameter:
# - current fldname
# - missing trigger layout
sub process_missing_trigger
{
    my $current_fldname = uc shift;
    my $layout          = shift;
    my $rangecode;
    my @condition = split /=/, $layout;
    if ( defined( $condition[1] ) && $condition[1] =~ /^\s*\((.*)\)\s*$/ )
    {
        my ( $fldname, $values ) = split /:/, $1;
        $fldname = lc $fldname;

        return $rangecode if ( $fldname eq lc $current_fldname );

        $rangecode =
            qq{if $fldname in($values) and x in (m,n) then set_vals(fldname=\$x, value=m); return(true) if $fldname in($values) and x notin(m,n) then return('Error: Please leave this field blank.') endif };
    }

    return $rangecode;
}

# named parameters:
#  	- project
#  	- tblname
#	- db
# returns hash
sub process_id_layout
{
    my %args    = @_;
    my $project = lc $args{project};
    my $tblname = lc $args{tblname};
    my $dbo     = $args{db};

    my $str =
        qq{select layout from $project\_datadic where lower(tblname)='$tblname' and lower(fldname) = 'id' limit 1};
    my $str2 = $dbo->{db}->translate_sql($str);
    my $sth  = $dbo->{dbh}->prepare($str2)
        or warn "Couldn't prepare $str statement!\n";
    my $rv = $sth->execute or warn "Couldn't execute $str statement!\n";

    my $layout = $sth->fetchrow_array;
    return _get_layout_options_hash($layout);
}

# parameter: layout string
# returns: layout in hash
sub _get_layout_options_hash
{
    my $layout = shift;

    if ( !$layout )
    {
        return {};
    }

    my %layouts_h;
    foreach my $l_item ( split m/ \;/x, $layout )
    {
        $l_item = trim($l_item);
        if ( $l_item !~ / ^ \s*$/x )
        {
            my @val = split( m/=/x, $l_item, 2 );

            if ( $val[1] )
            {
                my $key   = trim( $val[0] );
                my $value = trim( $val[1] );
                $layouts_h{$key} = {
                    'key'           => $key,
                    'value'         => $value,
                    'layout_string' => qq{$key=$value}
                };
            }
            else
            {
                $layouts_h{$l_item} =
                    { 'key' => $l_item, 'layout_string' => $l_item };
            }
        }
    }

    return \%layouts_h;
}

#--------------------- translate_rangecode($prot, $dbo, $input, $debug) ---------------------#
# required parameters:
# 		$prot 	- protocol initial
#		$dbo  	- hash stores db and dbh database handlers
#		$input 	- range code
# optional parameter:
#		$debug 	- debug on (1), debug off (0)
sub translate_rangecode
{
    my $prot  = lc shift;
    my $dbo   = shift;
    my $input = shift;
    my $tbl   = shift;
    my $fld   = shift;
    my $debug = shift;

    # note: comment out the following line after debug
    #$debug=1;

    # check parameters
    if ( !$prot )
    {
        return ( { error => '400', msg => 'missing prot parameter' } );
    }
    if ( !$dbo->{db} )
    {
        return ( { error => '400', msg => 'missing dbo->{db} parameter' } );
    }
    if ( !$dbo->{dbh} )
    {
        return ( { error => '400', msg => 'missing dbo->{dbh} parameter' } );
    }

    # stores result from function call generate_datadic_info($prot, $dbo);
    my %datadic_info;

    # varaible stores the final output
    my $rangeprl;

    # error report
    my $error_report;

    # debug flag: 1 => on, 0 => off

    ##############
    # states
    my $STR_STATE    = 'STRING_STATE';
    my $STR_END      = 'STRING_END';
    my $BETW_STATE   = 'BETWEEN_STATE';
    my $NBETW_STATE  = 'NOT_BETWEEN_STATE';
    my $IN_STATE     = 'IN_STATE';
    my $NOTIN_STATE  = 'NOT_IN_STATE';
    my $NUM_STATE    = 'NUMERIC_STATE';
    my $KEY_STATE    = 'KEYWORD_STATE';
    my $VAR_STATE    = 'VARIABLE_STATE';
    my $Q3VAR_STATE  = 'Q3_VARIABLE_STATE_START';
    my $OPER_STATE   = 'OPERATOR_STATE';
    my $EXPR_STATE   = 'EXPRESSION_STATE';
    my $IF_STATE     = 'IF_STATE';
    my $THEN_STATE   = 'THEN_STATE';
    my $ELSE_STATE   = 'ELSE_STATE';
    my $IFSWITCH_END = 'END_IF_OR_SWITCH_STATE';

    # no .sql{} is allowed
    #	my $SQL_STATE 	  = 'SQL_STATE';
    # local variable declaration no longer supported
    # my $DECLARE_STATE = 'DECLARE_STATE';
    # my $DECLARE_END   = 'DECLARE_STATE_END';
    my $PERLSCRIPT = 'PERLSCRIPT_STATE';
    ##############

    # store each q3	query
    my %q3_info;
    my $current_q3_tbl;
    my $current_q3_prot;
    my $current_q3_localvar;

    # store full sql string
    #	my $sql;
    # flag indications that you are in a function
    my $function_flag = 0;

# flag indicates whether grouping is on (1) or off (0), e.g. {[x=1]} everything inside { } will be groupped together
# grouping is used with [] statement only
    my $grouping_flag = 0;

# flag for if then else statement, case statement, value: "", $IF_STATE, $THEN_STATE, $ELSE_STATE
    my $ifthenelse_flag = '';

    # flag for switch statement, value: 0, 1
    my $switch_flag = 0;

# flag for stack [] statement, indicate weather the current state is in a stack statement (to distinguish between if and stack statement, since they will be assigned to the same state)
    my $stack_flag = 0;

    # indicates whether the current rangeval contains a [] statement
    my $contains_stack_flag = 0;

# if there's a colon separater in the stack statement e.g. [:], set the flag to true
    my $colon_flag = 0;

    # check whether the field is an admin field or not
    my $is_admin_field;
    my %admin_field_h;

    #	my %admin_field_h = (
    #		'id' => 1,
    #		'rid'=> 1,
    #		'viscode' => 1,
    #		'siteid' => 1,
    #		'entry' => 1,
    #		'verify' => 1,
    #		'userid' => 1,
    #		'userdate' => 1,
    #		'userid2' => 1,
    #		'userdate2' => 1,
    #		'recno' => 1
    #	);
    #
    #	$is_admin_field = 1 if($admin_field_h{lc($fld)});

    if ( $prot && $tbl )
    {
        my @admin_fields =
            $dbo->{db}->tableadmincols( tablename => "$prot\_$tbl" );
        %admin_field_h = map { lc $_, 1 } @admin_fields;

# hard code, always assume recno is admin field, and skip the assumption on recno
        $admin_field_h{'recno'} = 1;
        $is_admin_field = 1 if ( $admin_field_h{ lc($fld) } );
    }

    my $uctbl = uc $tbl;
    my $ucfld = uc $fld;

    # get type, deciml, visibleval and layout information
    my $visible_str;
    my $str =
        qq{select ftype, type, deciml, layout, visibleval from $prot\_datadic where tblname=\'$uctbl\' and fldname=\'$ucfld\' order by tblname, colid limit 1};
    my $str2 = $dbo->{db}->translate_sql($str);
    my $sth  = $dbo->{dbh}->prepare($str2)
        or warn "Couldn't prepare $str statement!\n";
    my $rv = $sth->execute or warn "Couldn't execute $str statement!\n";

    my ( $fieldtype, $ftype, $deciml, $layout, $visible ) =
        $sth->fetchrow_array;
    $fieldtype =~ s/^\s+//;
    $fieldtype =~ s/\s+$//;

    # ftype default to text
    $fieldtype = 'T' unless ($fieldtype);

    my $letpass_date;
    my $ws_flag;
    my %ws_info;

    # default to true, could be local variable WS if calc is defined in layout
    my $input_return = 'true';
	my $missing_trigger;
	
# assumptions when rangeval is empty, escape when the field is an admin field
# system default: not allowing n if no rangeval is specified, except for field that is hidden
    if ( ( length($input) == 0 || $input =~ /^\s+$/ ) && !$is_admin_field )
    {

# first check if letpass is defined with a date, if so treat the letpass as the top priority
        if ( $layout =~ /letpass\s*=\s*(\d\d\/\d\d\/\d\d\d\d);?\b/i )
        {
            $letpass_date = $1 if ( length($1) );
        }

        # get ID layout, check for keyword missing_trigger
        my $id_layout = process_id_layout(
            db      => $dbo,
            project => $prot,
            tblname => $tbl
        );
        if ( exists $id_layout->{missing_trigger} )
        {
            $missing_trigger =
                process_missing_trigger( $fld,
                $id_layout->{missing_trigger}{layout_string} );
            $input = $missing_trigger;
        }

  		# new: next check if ws() function is defined in the layout, ws is lowercase
        if ( $layout =~ /calc\((.*)\)/ || $layout =~ /calc_i\((.*)\)/ )
        {
            $ws_flag = 1;
            my @wspost_param = split ",", $1;
            my $size_wspost_param = @wspost_param;
            if ( $size_wspost_param < 1 )
            {
                return (
                    {
                        error => '405',
                        msg =>
                            qq{Syntax Error: in layout, function calc requires at least 1 parameter.}
                    }
                );
            }
            else
            {
                $ws_info{"submit_only"} = "0";
                $ws_info{"filename"}    = trim( $wspost_param[0] );

       			# if there exist the second param, and check it's dest instead of alias
                if ( $wspost_param[1] && $wspost_param[1] =~ /:/ )
                {
                    return (
                        {
                            error => '405',
                            msg =>
                                qq{Syntax Error: in layout, function calc contains an invalid second parameter.}
                        }
                    );
                }
                $ws_info{"dest"} = trim( $wspost_param[1] )
                    if ( $wspost_param[1]
                    && lc( trim( $wspost_param[1] ) ) ne 'na' );
                $ws_info{"alias"} = trim( $wspost_param[2] )
                    if ( $wspost_param[2]
                    && lc( trim( $wspost_param[2] ) ) ne 'na' );
                if ( $layout =~ /calc\((.*)\)/ )
                {
                    $ws_info{"mode"} = "c";
                }
                elsif ( $layout =~ /calc_i\((.*)\)/ )
                {

          			# just another check, make sure the second param is always required
                    unless ( $ws_info{'dest'} )
                    {
                        return (
                            {
                                error => '405',
                                msg =>
                                    qq{Syntax Error: in layout, function calc_i missing second parameter.}
                            }
                        );
                    }
                    $ws_info{"mode"} = "i";
                }

            }
            $input        = qq{WS=|wspost|; };
            $input_return = 'WS';
        }

		# allow n if field is hidden
		# notes: mei moved this logic here on 3/3/2011, since visibleval need to take a higher precedence
        if ( exists $ws_info{'mode'} && $ws_info{'mode'} eq 'i' )
        {

            # 3/29/2011, should skip the visiblity cases when calc_i is called
            # if calc_i, do nothing here
        }
        else
        {
            if ( length($visible) > 0 && $visible !~ /^\s+$/ )
            {
                if ( $visible =~ /^\s*off\s*$/ )
                {
                    $visible_str =
                        qq{if x in (n) then return($input_return) };
                }
                elsif ( $visible =~ /^\s*on\s*\((.+)\)\s*$/ )
                {
                    if ($1)
                    {
                        $visible_str =
                            qq{if viscode notin ($1) and x in (n) then return($input_return) };
                    }
                }
                elsif ( $visible =~ /^\s*off\s*\((.+)\)\s*$/ )
                {
                    if ($1)
                    {
                        $visible_str =
                            qq{if viscode in ($1) and x in (n) then return($input_return) };
                    }
                }

            }
        }
        $input .= $visible_str if ( length($visible_str) > 0 );

        # check for bugs, the date defined for letpass has to be bbl format
        if ( $layout =~ /\bletpass\s*=\b/i && !$letpass_date )
        {
            return (
                {
                    error => '405',
                    msg =>
                        qq{Syntax Error: letpass date format is invalid (MM/DD/YYYY)}
                }
            );
        }

        # debug
        print qq{letpass_date: $letpass_date<br />} if ($debug);

# notes: mei moved this logic here on 5/3/2011, to encounter log form type earlier in the script
        if ( exists $ws_info{'mode'} && $ws_info{'mode'} eq 'i' )
        {

            # should skip the log form cases when calc_i is called
            # if calc_i, do nothing here
        }
        else
        {

            # if log form, allow n to pass in all the fields when recno < 0
            $str =
                qq{select layout from $prot\_datadic where tblname=\'$uctbl\' and fldname=\'ID\' limit 1};
            $str2 = $dbo->{db}->translate_sql($str);
            $sth  = $dbo->{dbh}->prepare($str2)
                or warn "Couldn't prepare $str statement!\n";
            $rv = $sth->execute or warn "Couldn't execute $str statement!\n";

            my $logform_layout = $sth->fetchrow_array;

            if ( $logform_layout =~ /log/i )
            {
                $input .=
                    qq{if recno < 0 and x=n then return($input_return) };
            }
        }

        if ( exists $ws_info{'mode'} && $ws_info{'mode'} eq 'i' )
        {

            # if calc_i, do nothing here
        }
        elsif ( $layout =~ /\bletpass\b/i && !$letpass_date )
        {

            # note: letpass should overwrite wspost()
            $input = 'true';
        }
        elsif ( uc($ftype) eq 'I' )
        {
        	if(defined $missing_trigger){
        		$input  = qq{$missing_trigger $input_return};
        	}else{
            	$input = $input_return;
            }
        }
        elsif (
            uc($ftype) eq 'T'
            && (   uc($fieldtype) eq 'P'
                || uc($fieldtype) eq 'T'
                || uc($fieldtype) eq 'PS' )
            && $layout !~ /indent\s*=\s*(\d+)/i
            && $layout !~ /subquestion\_trigger/
            && $layout !~ /text\_strict/i
            && $layout !~ /paragraph\_strict/i
            )
        {

# handle special case, when field type is a password (password is such a comment name, so assume only when field is type T)
            if ( ( $layout =~ /\bpassword\b/i || uc($fieldtype) eq 'PS' )
                && uc($ftype) eq 'T' )
            {
                $input .=
                    qq{ if password_check(x)!=1 then return('Invalid password!') else true };
            }
            elsif ( $layout =~ /\btime\_military\b/i && uc($ftype) eq 'T' )
            {

                # layout keyword "time_military", validate time
                $input .=
                    qq{ if time_validate(data=x)!=1 and x notin (m,n) then return('Invalid time (HHMM)!') else true };
            }
            elsif ( $layout =~ /\btime\_military\_strict\b/i
                && uc($ftype) eq 'T' )
            {

        # layout keyword "time_military_strict", validate time and not allow n
                $input .=
                    qq{ if time_validate(data=x)!=1 and x notin (m) then return('Invalid time (HHMM)!') else true };
            }
            else
            {

                # allow everything if field is text or paragraph with type T
				if(defined $missing_trigger){
        			$input  = qq{$missing_trigger $input_return};
				}else{
					$input = $input_return;
				}
            }
        }
        else
        {

# handle letpass date, if date is defined, let rangeval pass if userdate is before or equal to the date
            if ($letpass_date)
            {
                $input .=
                    qq{if date_validate(date='$letpass_date') and date_range_compare(date=userdate,lower_date='01/01/1800',upper_date='$letpass_date')>0 then return(true) };
            }

           # meta data information: binary checkbox info for the current table
            my $binary_res =
                get_binarycheckbox_info( $prot, $dbo, $tbl, $debug );
            my @binary_res2 = @{$binary_res};
            my %is_binarycheckboxgroup;
            my %binarycheckboxgroup_info;
            if ( scalar(@binary_res2) == 2 )
            {
                %is_binarycheckboxgroup   = %{ $binary_res2[0] };
                %binarycheckboxgroup_info = %{ $binary_res2[1] };
            }

# if field is one of the binary checkbox group fields, and not the last binary checkbox field, allow n to pass
            if ( exists $is_binarycheckboxgroup{ lc($fld) }
                && uc($fieldtype) ne 'KE' )
            {
                $input .= qq{if x=n then return($input_return) };
            }

            # get code options
            my $temp_a = get_code_option( $prot, $dbo, $tbl, $fld, $debug );
            my @options = @{$temp_a};
            my $option_length = @options;
            my $tempstr = join ",", @options;

# handle field dependent (layout contains "indent"), exclude binary non-last field
            my $indent_input;
            if (
                $layout =~ /subquestion\_trigger/i
                || (
                    $layout =~ /indent\s*=\s*(\d+)/i
                    && ( !exists $is_binarycheckboxgroup{ lc($fld) }
                        || $fieldtype eq 'KE' )
                )
                )
            {
                $layout =~ /indent\s*=\s*(\d+)/i;
                my $dependent_fld;
                $dependent_fld = lc(
                    get_dependent_field(
                        $prot, $dbo, $tbl, $fld, $1, $debug
                    )
                ) if ($1);
                $dependent_fld =~ s/^\s+//;
                $dependent_fld =~ s/\s+$//;

                # get dependent field layout
                $str =
                    qq{select layout from $prot\_datadic where tblname=\'$uctbl\' and fldname=\'}
                    . uc($dependent_fld)
                    . qq{\' limit 1};
                $str2 = $dbo->{db}->translate_sql($str);
                $sth  = $dbo->{dbh}->prepare($str2)
                    or warn "Couldn't prepare $str statement!\n";
                $rv = $sth->execute
                    or warn "Couldn't execute $str statement!\n";
                my $dependent_fld_layout = $sth->fetchrow_array;
                my $temp                 = $tempstr;
                if ( length($temp) > 0 )
                {

                    if ( $temp =~ /\d+\.\.\d+/ )
                    {
                        $temp =~ s/\.\./ to /g;
                    }
                    $temp = qq{[$temp]};
                }

                my $x_is_n_str    = qq{x=n};
                my $x_isnot_n_str = qq{x!=n};

                # in the case of the subquestion is a binary checkbox group
                if ( exists $is_binarycheckboxgroup{ lc($fld) }
                    && uc($fieldtype) eq 'KE' )
                {
                    my @temparray;
                    my @temparray2;
                    foreach
                        my $k ( @{ $binarycheckboxgroup_info{ lc($fld) } } )
                    {
                        $k = lc($k);
                        push @temparray,  qq{$k=n};
                        push @temparray2, qq{$k!=n};
                    }
                    $x_is_n_str    = join ' and ', @temparray;
                    $x_isnot_n_str = join ' or ',  @temparray2;
                }

                if ( $layout =~ /subquestion\_trigger/i )
                {

                    # prepare is_checkbox hash, key fldname
                    my %is_checkbox_hash;
                    if ($tbl)
                    {
                        $str =
                            qq{select fldname from $prot\_datadic where tblname=\'$uctbl\' and ftype='K'};
                        $str2 = $dbo->{db}->translate_sql($str);
                        $sth  = $dbo->{dbh}->prepare($str2)
                            or warn "Couldn't prepare $str statement!\n";
                        $rv = $sth->execute
                            or warn "Couldn't execute $str statement!\n";
                        while ( my $tempfld = $sth->fetchrow_array )
                        {
                            $tempfld =~ s/^\s+//;
                            $tempfld =~ s/\s+$//;
                            $is_checkbox_hash{ lc($tempfld) } = 1;
                        }
                    }
                    my $trigger_res =
                        get_subquestion_trigger( $layout,
                        \%is_checkbox_hash );
                    if (   uc($ftype) eq 'T'
                        && ( uc($fieldtype) eq 'T' || uc($fieldtype) eq 'P' )
                        && $layout !~ /text\_strict/i
                        && $layout !~ /paragraph\_strict/i )
                    {
                        if ( $layout =~ /\btime\_military\b/i )
                        {
                            $indent_input =
                                qq{if ($trigger_res->[1]) and ($x_isnot_n_str) then return('Error: Based on main question, please leave this field blank.') if ($trigger_res->[0]) and time_validate(data=x)!=1 and x notin (m,n) then return('Invalid time (HHMM)!') else return($input_return) endif };
                        }
                        elsif ( $layout =~ /\btime\_military\_strict\b/i )
                        {
                            $indent_input =
                                qq{if ($trigger_res->[1]) and ($x_isnot_n_str) then return('Error: Based on main question, please leave this field blank.') if ($trigger_res->[0]) and time_validate(data=x)!=1 and x notin (m) then return('Invalid time (HHMM)!') else return($input_return) endif };
                        }
                        else
                        {
                            $indent_input =
                                qq{if ($trigger_res->[1]) and ($x_isnot_n_str) then return('Error: Based on main question, please leave this field blank.') else return($input_return) endif };
                        }

                    }
                    else
                    {
                        $indent_input =
                            qq{if ($trigger_res->[0]) and ($x_is_n_str) then 'Error: Based on main question response to this field is required. ' if ($trigger_res->[1]) and ($x_isnot_n_str) then 'Error: Based on main question, please leave this field blank.' if ($trigger_res->[1]) and ($x_is_n_str) then return($input_return) };
                    }

                }
                else
                {
                    if ( length($dependent_fld) > 0 )
                    {

                        # extra time validateion
                        my $time_validation_code = '';
                        if ( $layout =~ /\btime\_military\b/i )
                        {
                            $time_validation_code =
                                qq{time_validate(data=x)!=1 and x notin (m,n) then return('Invalid time (HHMM)!')};
                        }
                        elsif ( $layout =~ /\btime\_military\_strict\b/i )
                        {
                            $time_validation_code =
                                qq{time_validate(data=x)!=1 and x notin (m) then return('Invalid time (HHMM)!')};
                        }

                        # subquestion logic
                        if (
                            exists $is_binarycheckboxgroup{
                                lc($dependent_fld) } )
                        {

# for binary check box groups as main question, trigger the subquestions when the all value in the binary checkbox group are not in(m,n)
                            my @temparray1;
                            my @temparray2;
                            foreach my $k (
                                @{
                                    $binarycheckboxgroup_info{
                                        lc($dependent_fld) }
                                }
                                )
                            {
                                $k = lc($k);
                                push @temparray1, qq{$k notin(m,n)};
                                push @temparray2, qq{$k in(m,n)};
                            }
                            my $tempstr1 = join ' or ',  @temparray1;
                            my $tempstr2 = join ' and ', @temparray2;
                            if (
                                (
                                    uc($ftype) eq 'T'
                                    && (   uc($fieldtype) eq 'T'
                                        || uc($fieldtype) eq 'P' )
                                    && $layout !~ /text\_strict/i
                                    && $layout !~ /paragraph\_strict/i
                                )
                                || (
                                    (
                                           uc($fieldtype) eq 'K'
                                        || uc($fieldtype) eq 'R'
                                    )
                                    && $option_length == 1
                                )
                                )
                            {

                        # for type T, text or paragraphs only force null value
                                if ( length($time_validation_code) > 0 )
                                {
                                    $time_validation_code =
                                        qq{if ($tempstr1) and }
                                        . $time_validation_code;
                                }
                                $indent_input =
                                    qq{if ($tempstr2) and ($x_isnot_n_str) then 'Error: Based on main question, please leave this field blank.' $time_validation_code else return($input_return) endif };
                            }
                            else
                            {
                                $indent_input =
                                    qq{if ($tempstr1) and ($x_is_n_str) then 'Error: Based on main question response to this field is required.' if ($tempstr2) and ($x_isnot_n_str) then 'Error: Based on main question, please leave this field blank.' if ($tempstr2) and ($x_is_n_str) then return($input_return) };
                            }
                        }
                        elsif ( $dependent_fld_layout =~ /\bcheck\b/i )
                        {

# for check box groups as main question, trigger the subquestions when the value is not in(m,n)
                            if (
                                (
                                    uc($ftype) eq 'T'
                                    && (   uc($fieldtype) eq 'T'
                                        || uc($fieldtype) eq 'P' )
                                    && $layout !~ /text\_strict/i
                                    && $layout !~ /paragraph\_strict/i
                                )
                                || (
                                    (
                                           uc($fieldtype) eq 'K'
                                        || uc($fieldtype) eq 'R'
                                    )
                                    && $option_length == 1
                                )
                                )
                            {

                        # for type T, text or paragraphs only force null value
                                if ( length($time_validation_code) > 0 )
                                {
                                    $time_validation_code =
                                        qq{if $dependent_fld notin(m,n) and }
                                        . $time_validation_code;
                                }
                                $indent_input =
                                    qq{if $dependent_fld in(m,n) and ($x_isnot_n_str) then 'Error: Based on main question, please leave this field blank.' $time_validation_code else return($input_return) endif };
                            }
                            else
                            {
                                $indent_input =
                                    qq{if $dependent_fld notin(m,n) and ($x_is_n_str) then 'Error: Based on main question response to this field is required.' if $dependent_fld in(m,n) and ($x_isnot_n_str) then 'Error: Based on main question, please leave this field blank.' if $dependent_fld in(m,n) and ($x_is_n_str) then return($input_return) };
                            }
                        }
                        else
                        {
                            if (
                                (
                                    uc($ftype) eq 'T'
                                    && (   uc($fieldtype) eq 'T'
                                        || uc($fieldtype) eq 'P' )
                                    && $layout !~ /text\_strict/i
                                    && $layout !~ /paragraph\_strict/i
                                )
                                || (
                                    (
                                           uc($fieldtype) eq 'K'
                                        || uc($fieldtype) eq 'R'
                                    )
                                    && $option_length == 1
                                )
                                )
                            {

                        # for type T, text or paragraphs only force null value
                                if ( length($time_validation_code) > 0 )
                                {
                                    $time_validation_code =
                                        qq{if (($dependent_fld>0 and is_numeric($dependent_fld)=1) or ($dependent_fld notin(n,m) and is_numeric($dependent_fld)=0)) and }
                                        . $time_validation_code;
                                }
                                $indent_input =
                                    qq{if ((is_numeric($dependent_fld)=1 and $dependent_fld <= 0) or (is_numeric($dependent_fld)=0 and $dependent_fld in(n,m))) and ($x_isnot_n_str) then return('Error: Based on main question, please leave this field blank.') $time_validation_code else return($input_return) endif };
                            }
                            else
                            {
                                $indent_input =
                                    qq{if (($dependent_fld>0 and is_numeric($dependent_fld)=1) or ($dependent_fld notin(n,m) and is_numeric($dependent_fld)=0)) and ($x_is_n_str) then 'Error: Based on main question response to this field is required.' if ((is_numeric($dependent_fld)=1 and $dependent_fld <= 0) or (is_numeric($dependent_fld)=0 and $dependent_fld in(n,m))) and ($x_isnot_n_str) then 'Error: Based on main question, please leave this field blank.' if ((is_numeric($dependent_fld)=1 and $dependent_fld <= 0) or (is_numeric($dependent_fld)=0 and $dependent_fld in(n,m))) and ($x_is_n_str) then return($input_return) };
                            }

                        }

                    }

                }
            }

# commented out by mei on 3/3/2011, moved visible logic to the top $input .= $visible_str  if ( length($visible_str) > 0 );
            $input .= $indent_input if ( length($indent_input) > 0 );

            if (   uc($ftype) eq 'T'
                && ( uc($fieldtype) eq 'T' || uc($fieldtype) eq 'P' )
                && $layout !~ /text\_strict/i
                && $layout !~ /paragraph\_strict/i
                && $indent_input )
            {

# skip text, paragraph when indent input is defined
# except when layout contains keyword "time_military", validate time
#				if($layout=~/\btime\_military\_strict\b/i){
#					# not allow n
#					$input .= qq{ if x notin (m) and time_validate(data=x)!=1then return('Invalid time (HHMM)!') else true };
#				}elsif($layout=~/\btime\_military\b/i){
#					$input .= qq{ if x notin (m,n) and time_validate(data=x)!=1 then return('Invalid time (HHMM)!') else true };
#				}
# in the last field of a binary checkbox group, check at least one field from the binary checkbox group is selected
            }
            elsif ( uc($fieldtype) eq 'KE' )
            {

                # get all field names belong to that binary check group
                my @temp_array = @{ $binarycheckboxgroup_info{ lc($fld) } };
                my $temp_str;
                foreach my $i ( 0 .. @temp_array - 1 )
                {
                    $temp_array[$i] = qq{$temp_array[$i] notin(n)};
                }
                $temp_str = join ' or ', @temp_array;
                $input .= qq{if $temp_str then $input_return };
                $input .=
                    qq{else 'Error: Field is required. Please complete.'};
            }

            # if code is defined, then allow c,m only
            elsif (
                length($tempstr)
                && (   uc($fieldtype) eq 'K'
                    || uc($fieldtype) eq 'C'
                    || uc($fieldtype) eq 'R'
                    || ( uc($ftype) eq 'N' && uc($fieldtype) eq 'T' ) )
                )
            {
                if ( uc($fieldtype) eq 'K' )
                {

# checkbox group, note: need a function to check the if x is within range of the code
# this is not working $input .= qq{if index(}.lc($fld).qq{, x)>-1 or x in (m) then true };
                    if ( $option_length == 1 )
                    {

                        # for only one checkbox, always allow true
                        $input .= qq{if true then return($input_return) };
                    }
                    else
                    {
                        $input .= qq{if x notin(n) then $input_return };
                    }

                }
                elsif ( $tempstr =~ /(\d+)\.\.(\d+)/ )
                {

           # combo box contains code syntax n1..n2[:step], [:step] is optional
           # combo box code syntax example, 1..2:0.5, 4, 55, 100..1000:30
                    my @conditions = split ',', $tempstr;
                    my @conditions2;
                    my $conditons_str;

                    foreach my $c (@conditions)
                    {
                        if ( $c =~ /(\d+)\.\.(\d+)/ )
                        {
                            $c =~ s/\s*:\s*/:/;
                            if (   $deciml
                                && $deciml > 0
                                && $c !~ /:\d+\.\d*$/ )
                            {
                                my $newdeciml = 0.1**$deciml;
                                $c .= qq{:$newdeciml};
                            }
                        }
                        push @conditions2, $c;
                    }
                    if ( scalar @conditions2 > 0 )
                    {
                        $conditons_str = join ',', @conditions2;
                    }
                    else
                    {
                        $conditons_str = join ',', @conditions;
                    }

                    $input .=
                        qq{if x in ($conditons_str) or x in (m) then $input_return };
                }
                else
                {
                    if ( uc($fieldtype) eq 'R' && $option_length == 1 )
                    {

                        # for only one radio button, always allow true
                        $input .= qq{if true then return($input_return) };
                    }
                    else
                    {

                        # code in syntax like: 1=yes;0=no
                        $input .=
                            qq{if x in ($tempstr) or x in (m) then $input_return };
                    }

                }
                $input .=
                    qq{if x in (n) then 'Error: Field is required. Please complete.' else 'Error: Value entered is out of range.'};

    # if type is D for date, then validate the date, and assume no future date
            }
            elsif ( uc($ftype) eq 'D' )
            {
                $input .= qq{if x in (m) then $input_return };
                $input .=
                    qq{if date_validate('date'=>x)>0 and date_range_compare('date'=>x,'lower_date'=>'01/01/1800')>0 then $input_return };
                $input .=
                    qq{else 'Error: Date is not valid. Please review.' };
            }
            else
            {

                # default rule: n(null value) does not allowed in the form
                $input .= qq{if x notin(n) then $input_return };
                $input .=
                    qq{else 'Error: Field is required. Please complete.'};
            }

        }
    }

    # variable remembers each state
    my $state = ' ';

    # handle special expression, c, n and m
    if ( $input =~ /^\s*[cmn]\s*,?\s*[cmn]?\s*,?\s*[cmn]?\s*$/ )
    {
        my @temp = split ",", $input;
        my @temp2;

        # refresh input
        $input = undef;

        # look for c, m or n, construct the in statement
        foreach my $t (@temp)
        {
            if ( $t =~ /^\s*[c]\s*$/ )
            {

                # get code options
                my $temp_a =
                    get_code_option( $prot, $dbo, $tbl, $fld, $debug );
                my @options = @{$temp_a};
                my $tempstr = join ",", @options;
                if ( length($tempstr) )
                {
                    if ( $tempstr =~ /(\d+)\.\.(\d+)/ && $deciml > 0 )
                    {
                        my @conditions = split ',', $tempstr;
                        my @conditions2;
                        my $conditons_str;

                        foreach my $c (@conditions)
                        {
                            if ( $c =~ /(\d+)\.\.(\d+)/ )
                            {
                                $c =~ s/\s*:\s*/:/;
                                if (   $deciml
                                    && $deciml > 0
                                    && $c !~ /:\d+\.\d*$/ )
                                {
                                    my $newdeciml = 0.1**$deciml;
                                    $c .= qq{:$newdeciml};
                                }
                            }
                            push @conditions2, $c;
                        }
                        if ( scalar @conditions2 > 0 )
                        {
                            $conditons_str = join ',', @conditions2;
                        }
                        else
                        {
                            $conditons_str = join ',', @conditions;
                        }

                        $input .= qq{if x in ($conditons_str) then true };
                    }
                    else
                    {
                        push @temp2, $tempstr;
                    }
                }

            }
            elsif ( $t =~ /^\s*[mn]\s*$/ )
            {
                push @temp2, $t;
            }
        }
        if ( scalar @temp2 > 0 )
        {
            $input .=
                  qq{if x in (}
                . ( join ",", @temp2 )
                . qq{) then true else false};
        }
    }

    if ( $input =~ /^perlscript\b/ && $input =~ /\bendperl$/ )
    {
        $input =~ s/^perlscript//;
        $input =~ s/endperl$//;

        return ( { result => '1', msg => $input } );
    }

    # adding space in places to ease the split
    # add one space in the front of ), [, and ],
    $input =~ s/(\S)([\[\)])/$1 $2/g;
    $input =~ s/(\S)(\])/$1 $2/g;

    # add one space on the back of (, ;, :, =, "," [, and ], exception =>
    $input =~ s/(\[)(\S)/$1 $2/g;
    $input =~ s/([(;=\]])(\S)/$1 $2/g;
    $input =~ s/= >/ => /g;
    $input =~ s/\[\s+\[/ \[\[ /g;
    $input =~ s/\]\s+\]/ \]\] /g;

    $input =~ s/:/ : /g;

    # exception when we don't need space around :
    $input =~ s/(https?)\s*:\s*\/\//$1:\/\//g;

    $input =~ s/(\S),/$1 ,/g;
    $input =~ s/,(\S)/, $1/g;

    #	$input =~ s/\]\s+-/ \]- /g;

    # add one space around + sign
    $input =~ s/(\S)\+/$1 \+/g;
    $input =~ s/\+(\S)/\+ $1/g;

    # add space after comma
    $input =~ s/','/', '/g;

    # spliting the range code by space, or newline characters
    my @array = split /[ \n\r]/, $input;

    # between state variables, queue keep tracks the two range numbers
    my @queue;
    my $between_variable;

    # notbetween state variables, queue keep tracks the two range numbers
    my @queue_notbetween;
    my $notbetween_variable;

    # keep tracks inside of an in_statement;
    my $in_statement;
    my $in_variable;

    # keep tracks inside of an notin_statement;
    my $notin_statement;
    my $notin_variable;

    # switch statement variable
    my $switch_variable;

    # local variables: queue storing locally/user defined variables.
    my %local_variables;
    my @local_variables;

    # remembers variable on the left hand side of a comparison operator
    my $last_variable;

    # error check: doube quotes not allowed
    if ( $input =~ /["]/g )
    {
        $error_report =
            qq{Syntax Error: double quotes are not allowed in range code \n};
        return ( { error => '405', msg => $error_report } );
    }
    my $rangeval;

# loop through each 'word', determine the current state, and push it to the final result
    foreach my $s (@array)
    {

        # debug #
        print qq{<br />s: $s ,state: $state, flag: $function_flag<br />}
            if ( $debug == 1 );
        $rangeval .= $s;

        # variables supports type list
        my $list_head;
        my $list_tail;
        my $separator;

        # error checking
        if ( $s eq '[[' || $s eq ']]' )
        {
            $error_report .=
                qq{Syntax Error: syntax [[ or ]] are not allowed.\n};
            return ( { error => '405', msg => $error_report } );
        }

#--- perl scripting statement: start with key "perlscript" end with key "endperl" ---#
        if ( $s =~ /^perlscript$/i && $state ne $STR_STATE )
        {
            $state = $PERLSCRIPT;
            next;
        }
        elsif ( $s =~ /^endperl$/i && $state ne $STR_STATE )
        {
            $state = '';
            next;
        }
        elsif ( $state eq $PERLSCRIPT )
        {
            $rangeprl .= $s;
            next;
        }

  #		#--- sql state end ---#
  #		elsif ($state eq $SQL_STATE && $s =~ /([^\}\;]*)\}\;$/) {
  #			if(!$sql){
  #				$error_report .= qq{Syntax Error: Please define sql string.\n};
  #		        return ( {error => '405', msg => $error_report } );
  #			}else{
  #				$sql .= qq{ $1};
  #				# force full sql string to limit 1
  #				$sql =~s/limit\s*\d+\s*$/limit 1/;
  #				$sql .= qq{ limit 1} if($sql !~ /limit\s*\d+\s*$/);
  #
  #				# push sql string to rangeprl
  #				$rangeprl .= qq{sql_select(sql=>qq{$sql }, hash_data=>1, master=>1); };
  #			}
  #			$state = '';
  #			$sql = undef;
  #			$s = undef;
  #			next;
  #		}
  #--- q3 end e.g.  };, or VISCODE='sc'};---#
        elsif ( $state eq $Q3VAR_STATE && $s =~ /([^\}\;]*)\}\;$/ )
        {
            my $where = $1;
            $q3_info{$current_q3_localvar}{range_sql} .= qq{ $where}
                if ($where);

            # overwrites limit clause
            $q3_info{$current_q3_localvar}{range_sql}
                =~ s/limit\s*(\d+)\s*$//;

            # push q3 variable to rangeprl
            my $new_where;
            if ( $q3_info{$current_q3_localvar}{range_sql}
                =~ /\s*where\s*(.+)/ )
            {
                $new_where = $1;

                # local variable: LOCALVAR -> $_LOCALVAR
                $new_where =~ s/([A-Z][A-Z0-9_]*)/\$\_$1/g;

                # check for field type, don't quote type numeric
                my $reg_op = qr/is|is\s+not|!=|=|>|>=|<|<=/;
                my $regexp =
                    qr/[a-z0-9_]+\s*$reg_op\s*\'\$\_[A-Z][A-Z0-9_]*\'/;
                my @temp_s = split /($regexp)/, $new_where;
                foreach my $i ( 0 .. @temp_s - 1 )
                {

                    # find pattern: field compare_operator $_LOCALVAR
                    $temp_s[$i]
                        =~ /([a-z0-9_]+)(\s*$reg_op\s*)\'(\$\_[A-Z][A-Z0-9_]*)\'/;
                    my $field = $1;

                    # check for field type
                    if (
                        $datadic_info{$current_q3_tbl}{field}{$field}{type}
                        eq 'n' )
                    {
                        $temp_s[$i]
                            =~ s/([a-z0-9_]+\s*$reg_op\s*)\'(\$\_[A-Z][A-Z0-9_]*)\'/$1$2/;
                    }
                    else
                    {

                        # if exists local variable, escape single quote
                        if ( $temp_s[$i] =~ /(\$\_[A-Z][A-Z0-9_]*)/ )
                        {
                            $q3_info{$current_q3_localvar}
                                {'localvar_escape_str'} .= qq{ $1=~s/'/''/; };
                        }

                    }

                }
                $new_where = join '', @temp_s;
                $q3_info{$current_q3_localvar}{range_sql}
                    =~ s/\s*where\s*(.+)/ where $new_where/;
            }

            # end clause catches group by or order by clause
            my $end_clause;
            if ( $q3_info{$current_q3_localvar}{range_sql}
                =~ /(group\s+by|order\s+by)(.*)$/i )
            {
                $q3_info{$current_q3_localvar}{range_sql}
                    =~ s/(group\s+by|order\s+by)(.*)$//i;
                $end_clause = $1 . $2;
            }

         # loop through table indexes, add missing conditions in sql statement
            my @temp_where;
            foreach
                my $k ( keys %{ $datadic_info{$current_q3_tbl}{'indexes'} } )
            {
                my $uk = uc $k;
                $k = lc $k;

# if index key doesn't exist in the where clause, add it (note, index key excludes RECNO, user needs to explicitly defines recno value)
                if ( $q3_info{$current_q3_localvar}{range_sql} !~ /\b$k\b/ )
                {

                    # check for field type, don't quote type numeric
                    if ( $datadic_info{$current_q3_tbl}{field}{$k}{type} eq
                        'n' )
                    {
                        push @temp_where, qq{$k=\$vals{$uk}};
                    }
                    else
                    {
                        push @temp_where, qq{$k=\'\$vals{$uk}\'};
                    }
                }
            }

            $q3_info{$current_q3_localvar}{range_sql} .= qq{ and }
                if ( $q3_info{$current_q3_localvar}{range_sql} !~ /where\s*$/
                && @temp_where );
            $q3_info{$current_q3_localvar}{range_sql} .= join ' and ',
                @temp_where;

            # add entry info
            if ( $datadic_info{$current_q3_tbl}{'ftype'} == 4 )
            {
                if (
                    $q3_info{$current_q3_localvar}{range_sql} =~ /where\s*$/ )
                {
                    $q3_info{$current_q3_localvar}{range_sql} .=
                        qq{ entry=4 };
                }
                else
                {
                    $q3_info{$current_q3_localvar}{range_sql} .=
                        qq{ and entry=4 };
                }
            }

            #add group by or order by clause
            $q3_info{$current_q3_localvar}{range_sql} .= qq{ $end_clause}
                if ($end_clause);

            # remove keyword "where" if no where clause
            $q3_info{$current_q3_localvar}{range_sql} =~ s/\s*where\s*$//;

            # always limt 1
            if ( $q3_info{$current_q3_localvar}{range_sql}
                =~ /limit\s*(\d+)\s*$/ )
            {
                $q3_info{$current_q3_localvar}{range_sql}
                    =~ s/limit\s*(\d+)\s*$/limit 1/;
            }
            else
            {
                $q3_info{$current_q3_localvar}{range_sql} .= qq{ limit 1};
            }

            # close sql_select statement
            $q3_info{$current_q3_localvar}{range_sql} .=
                q{\}, hash_data=>1, master=>1);};

            # push sql into rangeprl
            $rangeprl .=
                qq{ $q3_info{$current_q3_localvar}{'localvar_escape_str'} }
                if (
                exists $q3_info{$current_q3_localvar}{'localvar_escape_str'}
                );
            $rangeprl .= qq{ $q3_info{$current_q3_localvar}{range_sql}};

            $current_q3_localvar = undef;
            $current_q3_tbl      = undef;
            $s                   = undef;
            $state               = '';
            next;
        }

        #		#--- sql state, store sql string into $sql variable ---#
        #		elsif($state eq $SQL_STATE){
        #			$sql .= qq{$s };
        #			$s = undef;
        #			next;
        #		}
        #--- q3 variable where condition, e.g. registry{} ---#
        elsif ( $state eq $Q3VAR_STATE )
        {

            # gen %q3_info;
            $q3_info{$current_q3_localvar}{range_sql} .= qq{ $s};

            $s = undef;
            next;
        }

        #--- q3 variable reference, e.g. U.examdate ---#
        elsif ($s =~ /^\s*([A-Z0-9_]+)\.([a-z0-9_]+)(\;?)\s*$/
            && $s !~ /^\s*(\d+)\.(\d+)(\;?)\s*$/ )
        {

            # TODO
            my $local_var = q{$_} . uc $1;
            my $fld       = uc $2;
            if ( exists $q3_info{$local_var} )
            {
                $s =
                      $q3_info{$local_var}{range_var}
                    . q{->[0]\{}
                    . $fld . q{\}}
                    . $3;
            }
            elsif ( $local_variables{$local_var} )
            {
                $s = $local_var . q{->[0]\{} . $fld . q{\}} . $3;
            }
            else
            {
                $error_report .=
                    qq{Syntax Error: Local variable $local_var wasn't defined.\n};
                return ( { error => '405', msg => $error_report } );
            }
            $state         = $VAR_STATE;
            $last_variable = $s;
            $rangeprl .= $s;
            next;
        }

        # in statement
        if ( ( $s =~ /^(in\(?)$/i || $state eq $IN_STATE )
            && $state ne $STR_STATE )
        {

            #--- in statement start: in(value 1[, value 2, ]) ---#
            if ( $s =~ /^in/i )
            {

                # clean in statement variables, start fresh
                $in_statement = undef;
                $in_variable  = undef;

                # retreive in variable
                if ($last_variable)
                {
                    $in_variable = $last_variable;

                    # remove in variable from rangeprl
                    foreach my $l ( 0 .. length($last_variable) - 1 )
                    {
                        chop $rangeprl;
                    }
                }

   # for statements like this:  in(1,2,3), assume the in variable is $vals{$x}
                unless ($in_variable)
                {
                    if ($switch_flag)
                    {
                        $in_variable = $switch_variable;
                    }
                    else
                    {
                        $in_variable = qq{\$vals\{\$x\}};
                    }
                }

                # remove the in and ( from rangeprl
                $s =~ s/^(in)\(?//i;
                $state = $IN_STATE;
            }
            elsif ( $state eq $IN_STATE && $s =~ /\($/ )
            {

                # trim ( from rangeprl
                $s =~ s/\($//;
                $state = $IN_STATE;
            }

            #--- in statement end ---#
            elsif ( $state eq $IN_STATE && $s =~ /\)$/ )
            {

                # remove trailing ) from rangeprl
                $s =~ s/\)$//;
                $state = '';

                #--- handle things inside of an in statement ---#
                my @temp_array = split ',', $in_statement;
                my @temp_in;
                my @temp_between;

                # loops through each condition, push them into rangeprl
                foreach my $in (@temp_array)
                {

                    # trim leading and trailing whitespace
                    $in =~ s/^\s+//;
                    $in =~ s/\s+$//;

                    if ( $in =~ /^\s*c\s*$/ )
                    {

                        # get code options
                        my $temp_a =
                            get_code_option( $prot, $dbo, $tbl, $fld,
                            $debug );
                        my @options = @{$temp_a};
                        my $temp_code = join ",", @options;
                        if (   length($temp_code) > 0
                            && $temp_code =~ /(\d+)\.\.(\d+)/
                            && $deciml > 0 )
                        {
                            push @temp_between, $temp_code;
                        }
                        else
                        {
                            @temp_in = ( @temp_in, @options )
                                if ( scalar @options > 0 );
                        }

                    }

                    # in statement condition: numeric
                    elsif ( $in =~ /^\d*\.?\d+$/ )
                    {
                        push @temp_in, $in;
                    }

                    # in statement condition: special variables
                    elsif ( $in =~ /^(x|m|n|t|v|w|r|g)$/ )
                    {
                        if ( $in eq 'x' )
                        {
                            push @temp_in, qq{\$vals\{\$x\}};
                        }
                        else
                        {
                            push @temp_in, qq{\$\_$in};
                        }
                    }

       # in statement condition: .. range statement for integer numeric values
                    elsif ( $in =~ /^(\d+)(\.\.)(\d+)$/ )
                    {
                        push @temp_in, qq{$in};
                    }

            # in statement condition: .. range statement for alphabetic values
                    elsif ( $in =~ /^([a-z])(\.\.)([a-z])$/i )
                    {
                        push @temp_in, qq{$in};
                    }

               # in statement condition: treat everything else as plain string
                    else
                    {
                        push @temp_in, qq{q\{$in\}};
                    }
                }

                # insert in statement into the final rangeprl output
                if ( scalar @temp_in > 0 )
                {
                    $rangeprl = $rangeprl . 'in(' . $in_variable;
                    $rangeprl = $rangeprl . "," . ( join ",", @temp_in );
                    $rangeprl .= $s if ( length($s) > 0 );
                    $rangeprl .= ')';
                    if (@temp_between)
                    {
                        $rangeprl .= ' || ';
                    }
                }
                my @temp_between2;
                foreach my $c (@temp_between)
                {
                    $c =~ /(\d+)\.\.(\d+)/;
                    push @temp_between2,
                        qq{($in_variable>=$1 && $in_variable<=$2)};
                }
                $rangeprl .= ( join " || ", @temp_between2 )
                    if (@temp_between2);
                next;
            }

            # store things inside of in statement into variable $in_statement
            $in_statement .= $s;
            $s = undef;

        }

        # notin statement
        elsif ( ( $s =~ /^(notin\(?)$/i || $state eq $NOTIN_STATE )
            && $state ne $STR_STATE )
        {

            #--- notin statement start: notin(value 1[, value 2, ]) ---#
            if ( $s =~ /^notin/i )
            {

                # clean in statement variables, start fresh
                $notin_statement = undef;
                $notin_variable  = undef;

                # retreive in variable
                if ($last_variable)
                {
                    $notin_variable = $last_variable;

                    # remove in variable from rangeprl
                    foreach my $l ( 0 .. length($last_variable) - 1 )
                    {
                        chop $rangeprl;
                    }
                }

# for statements like this:  notin(1,2,3), assume the in variable is $vals{$x}
                unless ($notin_variable)
                {
                    if ($switch_flag)
                    {
                        $notin_variable = $switch_variable;
                    }
                    else
                    {
                        $notin_variable = qq{\$vals\{\$x\}};
                    }
                }

                # remove the notin and ( from rangeprl
                $s =~ s/^(notin)\(?//i;
                $state = $NOTIN_STATE;
            }
            elsif ( $state eq $NOTIN_STATE && $s =~ /\($/ )
            {

                # trim ( from rangeprl
                $s =~ s/\($//;
                $state = $NOTIN_STATE;
            }

            #--- notin statement end ---#
            elsif ( $state eq $NOTIN_STATE && $s =~ /\)$/ )
            {

                # remove trailing ) from rangeprl
                $s =~ s/\)$//;
                $state = '';

                #--- handle things inside of an notin statement ---#
                my @temp_array = split ',', $notin_statement;
                my @temp_in;
                my @temp_between;
                my @temp_between2;

                # loops through each condition, push them into rangeprl
                foreach my $in (@temp_array)
                {

                    # trim leading and trailing whitespace
                    $in =~ s/^\s+//;
                    $in =~ s/\s+$//;

                    if ( $in =~ /^\s*c\s*$/ )
                    {

                        # get code options
                        my $temp_a =
                            get_code_option( $prot, $dbo, $tbl, $fld,
                            $debug );
                        my @options = @{$temp_a};

                        my $temp_code = join ",", @options;
                        if (   length($temp_code) > 0
                            && $temp_code =~ /(\d+)\.\.(\d+)/
                            && $deciml > 0 )
                        {
                            push @temp_between, $temp_code;
                        }
                        else
                        {
                            @temp_in = ( @temp_in, @options )
                                if ( scalar @options > 0 );
                        }
                    }

                    # notin statement condition: numeric
                    elsif ( $in =~ /^\d*\.?\d+$/ )
                    {
                        push @temp_in, qq{$in};
                    }

                    # notin statement condition: special variables
                    elsif ( $in =~ /^(x|m|n|t|v|w|r|g)$/ )
                    {
                        if ( $in eq 'x' )
                        {
                            push @temp_in, qq{\$vals\{\$x\}};
                        }
                        else
                        {
                            push @temp_in, qq{\$\_$in};
                        }
                    }

    # notin statement condition: .. range statement for integer numeric values
                    elsif ( $in =~ /^(\d+)(\.\.)(\d+)$/ )
                    {
                        push @temp_in, qq{$in};
                    }

         # notin statement condition: .. range statement for alphabetic values
                    elsif ( $in =~ /^([a-z])(\.\.)([a-z])$/i )
                    {
                        push @temp_in, qq{$in};
                    }

            # notin statement condition: treat everything else as plain string
                    else
                    {
                        push @temp_in, qq{q\{$in\}};
                    }
                }

                # insert notin statement into the final rangeprl output
                if ( scalar @temp_in > 0 )
                {
                    $rangeprl = $rangeprl . 'notin(' . $notin_variable;
                    $rangeprl = $rangeprl . "," . ( join ",", @temp_in );
                    $rangeprl .= $s if ( length($s) > 0 );
                    $rangeprl .= ')';
                    if (@temp_between)
                    {
                        $rangeprl .= ' && ';
                    }
                }
                foreach my $c (@temp_between)
                {
                    $c =~ /(\d+)\.\.(\d+)/;
                    push @temp_between2,
                        qq{($notin_variable<$1 || $notin_variable>$2)};
                }
                $rangeprl .= ( join " && ", @temp_between2 )
                    if (@temp_between2);
                next;
            }

       # store things inside of notin statement into variable $notin_statement
            $notin_statement .= $s;
            $s = undef;

        }

#--- handle list: anything inside of () is considered a list, funcion call and in statement are also lists  ---#
#--- handle list start ---#
        elsif ($s =~ /^((\s*\w*\()+)([^)]*)([\)]*\,?\;?\s*)$/
            && $s !~ /^(if|case|and|or|true|false)\(?$/ )
        {
            $list_head = $1;

            # list body
            $s = $3;
            $list_tail = $4 if ( length($4) > 0 );

            if ( $list_head =~ /^\w+\($/ && $state ne $STR_STATE )
            {
                $function_flag++;
            }

# if the list is a function and it is inside a switch case statement, add "switch variable eq" in front of it
            if (   $list_head =~ /^\w+\($/
                && $state eq $IF_STATE
                && $switch_flag )
            {
                $list_head = qq{$switch_variable eq $list_head};
            }

        }

        #--- handle list end ---#
        elsif ( $s =~ /^([^\)]*)([\)]+\,?\;?\s*)$/ )
        {
            while ( $s =~ /\)/g )
            {
                if ( $function_flag > 0 )
                {
                    $function_flag--;
                }

            }
            $s         = $1;
            $list_tail = $2;
        }

#--- handle separator for list, e.g. the comma after blue (blue, red), or ; after the statement if ... then randonmize(rid);1 else... ---#
        if ( $s =~ /^([^\,\;]*)([\,\;])$/ )
        {
            $s         = $1;
            $separator = $2;
        }

        #--- handle end of a string ---#
        if (   ( $s =~ /\'$/ && $state eq $STR_STATE )
            || ( $s =~ /^\s*\'[^\']*\'$/ ) )
        {

            # handle switch case condition
            if (   $switch_flag
                && $s =~ /^\s*\'[^\']*\'$/
                && $state eq $IF_STATE )
            {
                $s = qq{$switch_variable eq $s};
            }

# if the string is an Rvalue for a comparison statement, like x='string', then change the comparison operator to string operator
            if ( $s =~ /^\s*\'[^\']*\'$/ )
            {
                $rangeprl =~ s/==\s*$/ eq /;
                $rangeprl =~ s/!=\s*$/ ne /;
                $rangeprl =~ s/[^=]>\s*$/ gt /;
                $rangeprl =~ s/<=\s*$/ lt /;
                $rangeprl =~ s/>=\s*$/ ge /;
                $rangeprl =~ s/<=\s*$/ le /;

                # handle string concat
                $rangeprl =~ s/\+\s*$/\./;
            }
            $state = $STR_END;
        }

        #--- handle string ---#
        elsif ( $state eq $STR_STATE && $s !~ /\'/ )
        {

            # no action needed
        }

        #--- handle start of a string ---#
        elsif ( $s =~ /^'/ && $s !~ /\'\+/ )
        {

# for switch statement case condition, add "$switch_variable eq" in front of the code
            if ( $switch_flag && $state eq $IF_STATE )
            {
                $s = qq{$switch_variable eq $s};
            }

# if the string is an Rvalue for a comparison statement, like x='string', then change the comparison operator to string operator
            $rangeprl =~ s/==\s*$/ eq /;
            $rangeprl =~ s/!=\s*$/ ne /;
            $rangeprl =~ s/[^=]>\s*$/ gt /;
            $rangeprl =~ s/<=\s*$/ lt /;
            $rangeprl =~ s/>=\s*$/ ge /;
            $rangeprl =~ s/<=\s*$/ le /;

            # handle string concat
            $rangeprl =~ s/\+\s*$/\./;

            $state = $STR_STATE;
        }

        #--- handle in statement ---#
        elsif ( $state eq $IN_STATE )
        {

            # keep pushing everything to $in_statement
            $in_statement .= qq{$s };
            $s     = undef;
            $state = $IN_STATE;
        }

        #--- handle notin statement ---#
        elsif ( $state eq $NOTIN_STATE )
        {

            # keep pushing everything to $notin_statement
            $notin_statement .= qq{$s };
            $s     = undef;
            $state = $NOTIN_STATE;
        }

#--- switch statement start, syntax: switch variable case ... then ... case ... then ... else
        elsif ( $s =~ /^(switch)$/i )
        {
            $switch_flag = 1;
            $s           = undef;
        }

#--- between statement start, syntax: between value1 and value 2 or var between value1 and value2 ---#
        elsif ( $s =~ /^(between)$/i )
        {
            $state = $BETW_STATE;

            # clean between statement variables, start fresh
            @queue            = ();
            $between_variable = undef;
            $s                = undef;

            # get between statement variable
            if ($last_variable)
            {

                # remove last variable from rangeprl
                $between_variable = $last_variable;
                foreach my $l ( 0 .. length($last_variable) - 1 )
                {
                    chop $rangeprl;
                }
            }

# for statements like this:  between 1 and 2, assume the varaible is $vals{$x}
            unless ($between_variable)
            {
                if ($switch_flag)
                {
                    $between_variable = $switch_variable;
                }
                else
                {
                    $between_variable = qq{\$vals\{\$x\}};
                }
            }

        }

#--- notbetween statement start, syntax: notbetween value1 and value 2 or var notbetween value1 and value2 ---#
        elsif ( $s =~ /^(notbetween)$/i )
        {
            $state = $NBETW_STATE;

            # clean notbetween statement variables, start fresh
            @queue_notbetween    = ();
            $notbetween_variable = undef;
            $s                   = undef;

            # get between statement variable
            if ($last_variable)
            {

                # remove last variable from rangeprl
                $notbetween_variable = $last_variable;
                foreach my $l ( 0 .. length($last_variable) - 1 )
                {
                    chop $rangeprl;
                }
            }

# for statements like this:  notbetween 1 and 2, assume the varaible is $vals{$x}
            unless ($notbetween_variable)
            {
                if ($switch_flag)
                {
                    $notbetween_variable = $switch_variable;
                }
                else
                {
                    $notbetween_variable = qq{\$vals\{\$x\}};
                }
            }

        }

        #--- grouping end ---#
        elsif ( $s =~ /^\s*\}\s*\{?\s*$/ )
        {
            $s =~ s/^\s*\}\s*\{?\s*$//;
            $grouping_flag = 0;

            if ( $state eq $THEN_STATE )
            {
                $s .= qq{;\}else{1;}};
                $ifthenelse_flag = '';
            }
        }

        #--- grouping start ---#
        elsif ( $s =~ /^\s*\{\s*$/ )
        {
            $s =~ s/^\s*\{\s*$//;
            $grouping_flag = 1;
        }

     #--- if statement or switch statement's case condition, [] statement ---#
        elsif ( $s =~ /^if\(*$/i || $s =~ /^case\(*$/i || $s =~ /^\[$/ )
        {
            if ( $s =~ /^\[$/ )
            {

                # error checking do not allow [] other code []
                if ( $contains_stack_flag && $rangeval !~ /[{\]]\s*\[$/ )
                {
                    $error_report .=
                        qq{Syntax Error: Please group [] statements.\n};
                    return ( { error => '405', msg => $error_report } );
                }

                $stack_flag          = 1;
                $colon_flag          = 0;
                $contains_stack_flag = 1;
            }

            # case, [ is equivalent to "if"
            $s =~ s/case/if/g;
            $s =~ s/\[/if/g;

            # check wether this is an elsif statement
            if ( $ifthenelse_flag eq $THEN_STATE )
            {

                # remove any trailing white spaces from rangeprl
                $rangeprl =~ s/\s+$//;
                $s = ';}els' . $s;
            }

            $state           = $IF_STATE;
            $ifthenelse_flag = $IF_STATE;

         # clean the last variable in the beginning of each if statement start
            $last_variable = undef;

            # wrapping the conditions with ()
            $s .= '(';
        }

        # [:] syntax
        elsif ( $s eq ':' && $stack_flag == 1 )
        {
            $s          = ' ){return ';
            $colon_flag = 1;
        }

        #--- check error for then statement or [] statement ---#
        elsif ( $s =~ /^(\S)+(then)$/i
            || ( $s =~ /^(\S)+(\])$/ && $s !~ /\]\]/ ) )
        {
            $error_report =
                qq{Syntax Error: Missing a space before then or ] keyword.\n$s};
            return ( { error => '405', msg => $error_report } );

            #--- then statement or [] statement ---#
        }
        elsif ( $s =~ /^(then)$/i || $s =~ /^(\])$/ )
        {
            $state           = $THEN_STATE;
            $ifthenelse_flag = $THEN_STATE;

            # wrapping the condition with ()
            $s = '){';
            my $operator_temp = $1;

            # for [] statement, add return value to true
            if ( $operator_temp =~ /^\]$/ )
            {
                $stack_flag = 0;
                if ($colon_flag)
                {
                    $s = '';
                }
                else
                {
                    $s .= qq{return 1};
                }
            }

          #			elsif ( $operator_temp =~ /^\]$/ && $customized_if_flag == 2) {
          #				$s = qq{;\}else\{1;\}};
          #				$state           = $IFSWITCH_END;
          #				$ifthenelse_flag = $state;
          #				$customized_if_flag = undef;
          #			}
          #			elsif ( $operator_temp =~ /^\]-$/ && $customized_if_flag == 1) {
          #				$s .= qq{return };
          #				$customized_if_flag = 2;
          #			}
          #			elsif ($operator_temp =~ /^\]\]$/) {
          #				$state           = $IFSWITCH_END;
          #				$ifthenelse_flag = $state;
          #				$s .= qq{return undef;\}else\{1;\}};
          #				$customized_if_flag = undef;
          #			}
        }

        #--- else statement ---#
        elsif ( $s =~ /^else$/i )
        {
            $state           = $ELSE_STATE;
            $ifthenelse_flag = $ELSE_STATE;

            # clean the switch statement related flags and variables
            $switch_flag     = 0;
            $switch_variable = undef;

            # end then statement, start else block
            # remove white spaces from rangeprl
            $rangeprl =~ s/\s+$//;
            $s = ';}' . $s . '{';
        }

#--- local variable declaration start : not supported any more ---#
#     elsif ( $s =~ /^declare$/i && $state ne $STR_STATE ) {
#         $s     = undef;
#         $state = $DECLARE_STATE;
#     }
#--- local variable declaration end : not supported any more ---#
#     elsif ( $s =~ /^enddeclare$/i && $state ne $STR_STATE ) {
#         $s     = undef;
#         $state = $DECLARE_END;
#     }
#--- end if statement or switch statement, both keywords are not needed for stand alone if/switch statement	---#
        elsif ( $s =~ /^endif$/i || $s =~ /^endswitch$/i )
        {
            $s               = q{;\}};
            $state           = $IFSWITCH_END;
            $ifthenelse_flag = $state;
        }

        #--- numeric constant ---#
        elsif ( $s =~ /^\-?\d*\.?\d+$/ )
        {

            # handle between statement
            if ( $state eq $BETW_STATE )
            {
                push @queue, $s;
                $s = undef;

                # end of the between statement
                if ( scalar @queue == 2 )
                {

                    # generate code and push to rangeprl, clean the queue
                    if ( $queue[0] eq '0' || $queue[1] eq '0' )
                    {
                        $s =
                            qq{($between_variable<=$queue[1]&&$between_variable>=$queue[0]&&length($between_variable)>0)};
                    }
                    else
                    {
                        $s =
                            qq{($between_variable<=$queue[1]&&$between_variable>=$queue[0])};
                    }
                    @queue            = ();
                    $between_variable = undef;
                    $state            = $NUM_STATE;
                }
            }

            # handle notbetween statement
            if ( $state eq $NBETW_STATE )
            {
                push @queue_notbetween, $s;
                $s = undef;

                # end of the between statement
                if ( scalar @queue_notbetween == 2 )
                {

                    # generate code and push to rangeprl, clean the queue
                    $s =
                        qq{($notbetween_variable>$queue_notbetween[1]||$notbetween_variable<$queue_notbetween[0])};

                    @queue_notbetween    = ();
                    $notbetween_variable = undef;
                    $state               = $NUM_STATE;
                }
            }

            # handle switch case statement
            elsif ( $switch_flag && $state eq $IF_STATE )
            {
                $s     = qq{$switch_variable == $s};
                $state = $NUM_STATE;
            }

# if this number is an Rvalue for a comparisons statement, such as var == 0, var >= 0 and var <= 0, add a check for length(...)>0
            if (   $s eq '0'
                && $last_variable
                && $rangeprl =~ /(\)*)\s*(==|>=|<=)\s*$/ )
            {
                my $op    = $2;
                my $extra = $1;
                $rangeprl =~ s/\s*(==|>=|<=)\s*$//;

# if the left hand side of operator is an expression, do not add length(xxx)>0 check
                if ($extra)
                {
                    $rangeprl .= qq{$op};
                    $rangeprl .= qq{0};
                    next;
                }

                foreach my $l ( 0 .. ( length($last_variable) ) - 1 )
                {
                    chop $rangeprl;
                }
                $state = $NUM_STATE;

# if the left hand side of operator is a + operator (which leads to be an expression on the left side), do not add length(xxx)>0 check
                if ( $rangeprl =~ /\+\s*$/ )
                {
                    $rangeprl .= qq{$last_variable$extra$op};
                    $rangeprl .= qq{0};
                    next;
                }
                $rangeprl .= qq{($last_variable$extra$op};
                $rangeprl .= qq{0&&length($last_variable)>0)};
                next;
            }
        }

        #--- keyword: true, false, and, or ---#
        elsif ( $s =~ /^\)?(true|false|and|or)\(?$/i )
        {

            # ignore keyword "and" for between statement
            if ( ( $state eq $BETW_STATE || $state eq $NBETW_STATE )
                && $s =~ /and/i )
            {
                $s = undef;
            }
            else
            {
                $state = $KEY_STATE;
                $s =~ s/true/1/;
                $s =~ s/false/undef/;
                $s =~ s/and/\&\&/;
                $s =~ s/or/\|\|/;
            }
        }

     #		# .sql start
     #		elsif ($s=~/^\.sql\{(.*)(\}?)/){
     #			if($2){
     #				$error_report .= qq{Syntax Error: please define full sql string.\n};
     #		        return ( {error => '405', msg => $error_report } );
     #			}
     #
     #			$sql .= qq{$1 };
     #			$state = $SQL_STATE;
     #			$s=undef;
     #			next
     #		}
     #--- q3 start: e.g. registry{
        elsif ( $s =~ /^([a-z0-9_]+)\{([^\{\}\;]*)(\}?\;?)$/ )
        {
            $state          = $Q3VAR_STATE;
            $current_q3_tbl = lc $1;
            my $where  = $2;
            my $end_q3 = $3;

# if it is a cross project table e.g. prot__tblname, store the project name in variable $current_q3_prot
            if ( $current_q3_tbl =~ /([a-z0-9]+)\_\_([a-z0-9_]+)/ )
            {
                $current_q3_prot = $1;
                $current_q3_tbl  = $2;
            }
            else
            {
                $current_q3_prot = $prot;
            }

            # generate datadic info only when necessary
            if ( !%datadic_info || !exists $datadic_info{$current_q3_prot} )
            {
                %datadic_info = %{
                    generate_datadic_info( $current_q3_prot, $dbo,
                        \%datadic_info, $debug )
                };

                # check errors
                if ( $datadic_info{'error'} )
                {
                    return (
                        {
                            error => $datadic_info{'error'},
                            msg   => $datadic_info{'msg'}
                        }
                    );
                }
            }

            if ( $current_q3_tbl
                && exists $datadic_info{$current_q3_prot}{$current_q3_tbl} )
            {

# capture the local variable assigned to this q3 table, e.g. U=registry{}; ---> capture variable "U"
                $rangeprl =~ s/\$\_([A-Z0-9_]+)\s*\=\s*$//;
                if ($1)
                {
                    $current_q3_localvar = '$_' . $1;
                    pop @local_variables;
                    delete $local_variables{$current_q3_localvar};

                    # gen %q3_info
                    $q3_info{$current_q3_localvar}{range_var} =
                        '$TBL_PT_' . uc($1);
                    $q3_info{$current_q3_localvar}{range_sql} =
                          'my $TBL_PT_'
                        . uc($1)
                        . '=sql_select(sql=>qq{select * from '
                        . $current_q3_prot . '_'
                        . $current_q3_tbl
                        . ' where '
                        . $where;

                    # q3 end
                    if ( length($end_q3) )
                    {

                        # overwrites limit clause
                        $q3_info{$current_q3_localvar}{range_sql}
                            =~ s/limit\s*(\d+)\s*$//;

# interoperate local variables in sql string: treat all CAPS as local variables
                        my $new_where;
                        if ( $q3_info{$current_q3_localvar}{range_sql}
                            =~ /\s*where\s*(.+)/ )
                        {
                            $new_where = $1;

                            # local variable: LOCALVAR -> $_LOCALVAR
                            $new_where =~ s/([A-Z][A-Z0-9_]*)/\$\_$1/g;

                            # check for field type, don't quote type numeric
                            my $reg_op = qr/is|is not|!=|=|>|>=|<|<=/;
                            my $regexp =
                                qr/[a-z0-9_]+\s*$reg_op\s*\'\$\_[A-Z][A-Z0-9_]*\'/;
                            my @temp_s = split /($regexp)/, $new_where;
                            foreach my $i ( 0 .. @temp_s - 1 )
                            {

                             # find pattern: field compare_operator $_LOCALVAR
                                $temp_s[$i]
                                    =~ /([a-z0-9_]+)(\s*$reg_op\s*)\'(\$\_[A-Z][A-Z0-9_]*)\'/;
                                my $field = $1;

                                if ( $datadic_info{$current_q3_prot}
                                    {$current_q3_tbl}{field}{$field}{type} eq
                                    'n' )
                                {

                # check for field type, remove quotes if field type is numeric
                                    $temp_s[$i]
                                        =~ s/([a-z0-9_]+\s*$reg_op\s*)\'(\$\_[A-Z][A-Z0-9_]*)\'/$1$2/;
                                }
                                else
                                {

                               # if exists local variable, escape single quote
                                    if ( $temp_s[$i]
                                        =~ /(\$\_[A-Z][A-Z0-9_]*)/ )
                                    {
                                        $q3_info{$current_q3_localvar}
                                            {'localvar_escape_str'} .=
                                            qq{ $1=~s/'/''/; };
                                    }
                                }
                            }
                            $new_where = join '', @temp_s;
                            $q3_info{$current_q3_localvar}{range_sql}
                                =~ s/\s*where\s*(.+)/ where $new_where/;
                        }

                        # end clause catches group by or order by clause
                        my $end_clause;
                        if ( $q3_info{$current_q3_localvar}{range_sql}
                            =~ /(group\s+by|order\s+by)(.*)$/i )
                        {
                            $q3_info{$current_q3_localvar}{range_sql}
                                =~ s/(group\s+by|order\s+by)(.*)$//i;
                            $end_clause = $1 . $2;
                        }

         # loop through table indexes, add missing conditions in sql statement
                        my @temp_where;
                        foreach my $k (
                            keys %{
                                $datadic_info{$current_q3_prot}
                                    {$current_q3_tbl}{'indexes'}
                            }
                            )
                        {
                            my $uk = uc $k;
                            $k = lc $k;

# if index key doesn't exist in the where clause, add it (note, index key excludes RECNO, user needs to explicitly defines recno value)
                            if ( $q3_info{$current_q3_localvar}{range_sql} !~
                                /\b$k\b/ )
                            {

                              # check for field type, don't quote type numeric
                                if ( $datadic_info{$current_q3_prot}
                                    {$current_q3_tbl}{field}{$k}{type} eq
                                    'n' )
                                {
                                    push @temp_where, qq{$k=\$vals{$uk}};
                                }
                                else
                                {
                                    push @temp_where, qq{$k=\'\$vals{$uk}\'};
                                }
                            }
                        }
                        $q3_info{$current_q3_localvar}{range_sql} .=
                            qq{ and }
                            if ( $q3_info{$current_q3_localvar}{range_sql} !~
                            /where\s*$/ && @temp_where );
                        $q3_info{$current_q3_localvar}{range_sql} .=
                            join ' and ', @temp_where;

                        # add entry info
                        if ( $datadic_info{$current_q3_prot}{$current_q3_tbl}
                            {'ftype'} == 4 )
                        {
                            if ( $q3_info{$current_q3_localvar}{range_sql}
                                =~ /where\s*$/ )
                            {
                                $q3_info{$current_q3_localvar}{range_sql} .=
                                    qq{ entry=4 };
                            }
                            else
                            {
                                $q3_info{$current_q3_localvar}{range_sql} .=
                                    qq{ and entry=4 };
                            }
                        }

                        #add group by or order by clause
                        $q3_info{$current_q3_localvar}{range_sql} .=
                            qq{ $end_clause}
                            if ($end_clause);

                        # remove keyword "where" if no condition is defined
                        $q3_info{$current_q3_localvar}{range_sql}
                            =~ s/\s*where\s*$//;

                        # always limt 1
                        if ( $q3_info{$current_q3_localvar}{range_sql}
                            =~ /limit\s*(\d+)\s*$/ )
                        {
                            $q3_info{$current_q3_localvar}{range_sql}
                                =~ s/limit\s*(\d+)\s*$/limit 1/;
                        }
                        else
                        {
                            $q3_info{$current_q3_localvar}{range_sql} .=
                                qq{ limit 1};
                        }

                        # close sql_select function call
                        $q3_info{$current_q3_localvar}{range_sql} .=
                            q{\}, hash_data=>1, master=>1);};

                        # push sql statement to rangeprl
                        $rangeprl .=
                            qq{ $q3_info{$current_q3_localvar}{'localvar_escape_str'} }
                            if (
                            exists $q3_info{$current_q3_localvar}
                            {'localvar_escape_str'} );
                        $rangeprl .=
                            qq{ $q3_info{$current_q3_localvar}{range_sql}};
                        $current_q3_localvar = undef;
                        $current_q3_tbl      = undef;
                        $current_q3_prot     = undef;
                        $state               = '';

                    }
                }
                else
                {
                    $error_report .=
                        qq{Syntax Error: Q3 table $current_q3_tbl needs to be assign to a local variable.\n};
                    return ( { error => '405', msg => $error_report } );
                }
            }
            else
            {

                # capture error
                $error_report .=
                    qq{Syntax Error: Table $current_q3_tbl doesn't exist.\n};
                return ( { error => '405', msg => $error_report } );
            }

            $s = undef;
            next;

        }

        #--- variables: bareword and x, m, n, t, v, w, r, g ---#
        elsif ( $s =~ /^(\w+|x|m|n|t|v|w|r|g)$/ )
        {

            # special variables: $_m, $_n, $_t, $_v, $_w, $_r, $_g
            if ( $1 =~ /^(m|n|t|v|w|r|g)$/ )
            {
                $s = qq{\$\_$1};
            }

            # $vals{$x}
            elsif ( $1 =~ /^x$/ )
            {
                $s =~ s/x/\$vals\{\$x\}/;
            }
            else
            {

# declare statement is no longer supported : if ( $state eq $DECLARE_STATE && $s =~ /^([A-Z0-9_]+)$/ ) {

                # local variables
                if ( $s =~ /^([A-Z0-9_]+)$/ )
                {

# local variable declaration process, stores the local variables, add $_ infront of local vars
                    $s = qq{\$\_$s};

                    push @local_variables, $s unless ( $local_variables{$s} );
                    $local_variables{$s} = 1;
                }

                # variables points to fields
                else
                {

                    # declare statement is no longer supported
                    #                 if ( $s =~ /^([A-Z0-9_]+)$/ ) {
                    #                     $s = qq{\$\_$s};
                    #                     $local_variables{$s} = 1;
                    #                 }
                    #                 else {
                    $s = uc $1;
                    $s = qq{\$vals\{\'$s\'\}};

                    #                 }
                }
            }

# remembers the variable for case like x= 0 inside a condition statement, in order to add check length(..)>0
            $last_variable = $s;
            print qq{last variable: $last_variable\n} if ( $debug == 1 );

            # for switch statment, assume this is the switch variable
            if ( $switch_flag && !$switch_variable )
            {
                $switch_variable = $s;
                $s               = undef;
            }

            # for between statement:  between $x and $y
            elsif ( $state eq $BETW_STATE )
            {

                # if still inside a between statement
                push @queue, $s;
                $s = undef;

                # check whether it's the end of the between statement
                if ( scalar @queue == 2 )
                {
                    $state = $VAR_STATE;

   # end of between statement, generate rangeprl code, and clean the variables
                    $s =
                        qq{($between_variable <= $queue[1] && $between_variable >= $queue[0])};
                    @queue            = ();
                    $between_variable = undef;
                }
            }

            # for notbetween statement:  notbetween $x and $y
            elsif ( $state eq $NBETW_STATE )
            {

                # if still inside a between statement
                push @queue_notbetween, $s;
                $s = undef;

                # check whether it's the end of the between statement
                if ( scalar @queue_notbetween == 2 )
                {
                    $state = $VAR_STATE;

   # end of between statement, generate rangeprl code, and clean the variables
                    $s =
                        qq{($notbetween_variable > $queue_notbetween[1] || $notbetween_variable < $queue_notbetween[0])};
                    @queue_notbetween    = ();
                    $notbetween_variable = undef;
                }
            }

            # for switch statement
            elsif ( $state eq $IF_STATE && $switch_flag )
            {
                $s = qq{$switch_variable==$s};
            }
            else
            {
                $state = $VAR_STATE;
            }
        }

        #--- operator: >, <, >=, <=, !=, =, +, -, *, /, **, % ---#
        elsif ( $s =~ /^(\>|\<|\>\=|\<\=|=>|\!\=|\=|\+|\-|\*|\/|\*\*|\%)$/i )
        {

# if left hand side of an comparison operator doesn't have a variable, add $vals{$x}
            if (   $s =~ /^(\>|\<|\>\=|\<\=|\!\=|\=)$/i
                && $state ne $VAR_STATE
                && $state ne $EXPR_STATE
                && $state ne $STR_END
                && $state ne $NUM_STATE
                && $rangeprl !~ /\)\s*$/ )
            {
                $s             = qq{\$vals\{\$x\}$s};
                $last_variable = qq{\$vals\{\$x\}};
                print qq{last variable2: $last_variable\n} if ( $debug == 1 );
            }

# if operator = inside an if/case/[] statement condition, then treat it as a comparison operator
            if ( $ifthenelse_flag eq $IF_STATE && $s eq '=' )
            {
                $s = '==';
            }

# if operator = is an assignment operator, check the left hand side of the assignment, no special variables are allowed as LValues
            elsif (
                $s eq '='
                && (   $last_variable =~ /\$\_(m|n|v|w|r|g)\s*/
                    || $last_variable =~ /^\$vals/ )
                )
            {
                $error_report .=
                    qq{Syntax Error: variable $last_variable is not a valid LValue for variable assignment\n};
                return ( { error => '405', msg => $error_report } );
            }

# string concat when operator is +, requires that either LValue or RValue is a string
            if ( $rangeprl =~ /\'\s*$/ && $state ne $STR_STATE )
            {
                $s =~ s/\+/\./;
            }

            $state = $OPER_STATE;
        }

        #--- expression ---#
        else
        {

            # handle in statement
            if ( $state eq $IN_STATE )
            {

                # in statement ends
                if ( $s =~ /\)$/ )
                {

                    # remove trailing )
                    $s =~ s/\)\s*$//;
                    $state = '';

                    #--- translate in statement into rangeprl ---#
                    my @temp_array = split ',', $in_statement;
                    my @temp_in;
                    my @temp_between;
                    my @temp_between2;

                    foreach my $in (@temp_array)
                    {
                        if ( $in =~ /^\s*c\s*$/ )
                        {

                            # get code options
                            my $temp_a =
                                get_code_option( $prot, $dbo, $tbl, $fld,
                                $debug );
                            my @options = @{$temp_a};
                            my $temp_code = join ",", @options;
                            if (   length($temp_code) > 0
                                && $temp_code =~ /(\d+)\.\.(\d+)/
                                && $deciml > 0 )
                            {
                                push @temp_between, $temp_code;
                            }
                            else
                            {
                                @temp_in = ( @temp_in, @options )
                                    if ( scalar @options > 0 );
                            }
                        }

                        # number
                        elsif ( $in =~ /^\d+$/ )
                        {
                            push @temp_in, qq{$in};
                        }

                        # special variables
                        elsif ( $in =~ /^(x|m|n|t|v|w|r|g)$/ )
                        {
                            if ( $in eq 'x' )
                            {
                                push @temp_in, qq{\$vals\{\$x\}};
                            }
                            else
                            {
                                push @temp_in, qq{\$\_$in};
                            }
                        }

                        # range expression, e.g. 1..5
                        elsif ( $in =~ /^(\d+)(\.\.)(\d+)$/ )
                        {
                            push @temp_in, qq{$in};
                        }

                        # range expression, e.g. a-z
                        elsif ( lc $in =~ /^([a-z])(\.\.)([a-z])$/i )
                        {
                            push @temp_in, qq{$in};
                        }

                        # treat everything else as string
                        else
                        {
                            push @temp_in, qq{q\{$in\}};
                        }
                    }

                    # insert in statement into the final rangeprl output
                    if ( scalar @temp_in > 0 )
                    {
                        $rangeprl = $rangeprl . 'in(' . $in_variable;
                        $rangeprl = $rangeprl . "," . ( join ",", @temp_in );
                        $rangeprl .= ')';
                        if (@temp_between)
                        {
                            $rangeprl .= ' || ';
                        }
                    }
                    my @temp_between2;
                    foreach my $c (@temp_between)
                    {
                        $c =~ /(\d+)\.\.(\d+)/;
                        push @temp_between2,
                            qq{($in_variable>=$1 && $in_variable<=$2)};
                    }
                    $rangeprl .= ( join " || ", @temp_between2 )
                        if (@temp_between2);
                    next;
                }

# store everything inside of in statement to variable $in_statement, process them in the end of the in statement
                else
                {
                    $in_statement .= $s;
                    $s = undef;
                }
            }

            # handle noin statement
            if ( $state eq $NOTIN_STATE )
            {

                # notin statement ends
                if ( $s =~ /\)$/ )
                {

                    # remove trailing )
                    $s =~ s/\)\s*$//;
                    $state = '';

                    #--- translate notin statement into rangeprl ---#
                    my @temp_array = split ',', $notin_statement;
                    my @temp_in;
                    my @temp_between;
                    my @temp_between2;

                    foreach my $in (@temp_array)
                    {
                        if ( $in =~ /^\s*c\s*$/ )
                        {

                            # get code options
                            my $temp_a =
                                get_code_option( $prot, $dbo, $tbl, $fld,
                                $debug );
                            my @options = @{$temp_a};
                            my $temp_code = join ",", @options;
                            if (   length($temp_code) > 0
                                && $temp_code =~ /(\d+)\.\.(\d+)/
                                && $deciml > 0 )
                            {
                                push @temp_between, $temp_code;
                            }
                            else
                            {
                                @temp_in = ( @temp_in, @options )
                                    if ( scalar @options > 0 );
                            }
                        }

                        # number
                        elsif ( $in =~ /^\d+$/ )
                        {
                            push @temp_in, qq{$in};
                        }

                        # special variables
                        elsif ( $in =~ /^(x|m|n|t|v|w|r|g)$/ )
                        {
                            if ( $in eq 'x' )
                            {
                                push @temp_in, qq{\$vals\{\$x\}};
                            }
                            else
                            {
                                push @temp_in, qq{\$\_$in};
                            }
                        }

                        # range expression, e.g. 1..5
                        elsif ( $in =~ /^(\d+)(\.\.)(\d+)$/ )
                        {
                            push @temp_in, qq{$in};
                        }

                        # range expression, e.g. a-z
                        elsif ( lc $in =~ /^([a-z])(\.\.)([a-z])$/i )
                        {
                            push @temp_in, qq{$in};
                        }

                        # treat everything else as string
                        else
                        {
                            push @temp_in, qq{q\{$in\}};
                        }
                    }

                    # insert notin statement into the final rangeprl output
                    if ( scalar @temp_in > 0 )
                    {
                        $rangeprl = $rangeprl . 'notin(' . $notin_variable;
                        $rangeprl = $rangeprl . "," . ( join ",", @temp_in );
                        $rangeprl .= ')';
                        if (@temp_between)
                        {
                            $rangeprl .= ' && ';
                        }
                    }
                    foreach my $c (@temp_between)
                    {
                        $c =~ /(\d+)\.\.(\d+)/;
                        push @temp_between2,
                            qq{($notin_variable<$1 || $notin_variable>$2)};
                    }
                    $rangeprl .= ( join " && ", @temp_between2 )
                        if (@temp_between2);
                    next;
                }

# store everything inside of in statement to variable $in_statement, process them in the end of the in statement
                else
                {
                    $notin_statement .= $s;
                    $s = undef;
                }
            }

            # if expression is a string, the do nothing
            elsif ( $state eq $STR_STATE )
            {

                # if still inside a string
                $state = $STR_STATE;
            }

# variable operator value, variable operator variable, operator value|variable, function operator function, etc
            if ( $s
                =~ /^(\w*\.?[A-Z0-9_]*)(\)*)(=|>|<|>=|<=|!=|=>|\+|\-|\*|\/|\*\*|\%)(\(*\'?)(-?\d*\.?\d+|\w*\'?\(?)$/i
                )
            {
                print 'EXPR_STATE1: variable operator variable <br />'
                    if ($debug);

                # check for named parameters
                if ( $function_flag > 0 && $s =~ /^(\w+)\=$/ )
                {
                    $s     = qq{\'$1\'=>};
                    $state = "NAMED_PARAMETER";
                    $rangeprl .= qq{$s};
                    next;
                }

                # $l $op $r --> a=10
                my $l  = $1;
                my $op = $3;
                my $r  = $5;

                # )
                my $extra1 = $2;
                while ( $extra1 =~ /\)/g )
                {
                    if ( $function_flag > 0 )
                    {
                        $function_flag--;
                    }

                }

                # (, '
                my $extra2 = $4;

                #print qq{\n $l - $extra1 - $op - $extra2- $r \n};

         #--- handle value on the left hand side of the operator (LValue) ---#
                if (   ( length($l) == 0 || $l =~ /\s+/g || $l =~ /^x$/ )
                    && length($r) != 0
                    && !$extra1
                    && $state ne $VAR_STATE )
                {

# if no variable on the left hand side of a comparison operator, and the previous state is not a variable state, assume it is $vals{$x}
# note: functions or ) are allowed on the left handside
                    $l = '$vals{$x}'
                        if ( $op =~ /\=|\>|\<|\>\=|\<\=|\!\=/
                        && $rangeprl !~ /\)\s*$/ );
                }

                # special variables
                elsif ( $l =~ /^(m|n|t|v|w|r|g)$/ )
                {
                    $l = qq{\$\_$l};
                }

                # $vals{$x}
                elsif ( $l =~ /^\s*[x]\s*$/ )
                {
                    $l = '$vals{$x}';
                }

         # variables: q3 pointer(REG.examdate), $vals{'FIELD'}, and $_LOCALVAR
                elsif ( $l =~ /^\w+(\.[a-z][a-z0-9_]*)?$/ && $l !~ /^\d+$/ )
                {
                    if ( $l =~ /^([A-Z][A-Z0-9_]*)\.([a-z][a-z0-9_]*)$/ )
                    {
                        $l = qq{\$\_$1\-\>\[0\]\{} . uc $2 . qq{\}};
                    }
                    elsif ( $l =~ /^([A-Z0-9_]+)$/ )
                    {
                        $l = qq{\$\_$l};
                        push @local_variables, $l
                            unless ( $local_variables{$l} );
                        $local_variables{$l} = 1;
                    }
                    else
                    {
                        $l = uc $l;
                        $l = qq{\$vals\{\'$l\'\}};
                    }
                }

        #--- handle value on the right hand side of the operator (RValue) ---#
        # special variables
                if ( $r =~ /^\s*(m|n|t|v|w|r|g)\s*$/ )
                {
                    $r = qq{\$\_$r};
                }

                # TRUE and FALSE keywords
                elsif ( $r =~ /^\s*(true|false)\s*$/i )
                {
                    $r =~ s/true/1/i;
                    $r =~ s/false/undef/i;
                }

# if RValue is 0, and operator is = or != comparison operator, then add check for length(variable)>0
                elsif ($r =~ /^0$/
                    && length($r) > 0
                    && !$extra1
                    && $op =~ /=$/
                    && $op !~ /!=$/ )
                {
                    $r .= qq{&&length($l) > 0)};
                    $l = '(' . $l;
                }

                # $vals{$x}
                elsif ( lc $r =~ /^\s*[x]\s*$/ )
                {
                    $r = '$vals{$x}';
                }

                # variable $vals{'FIELD'} or $_LOCALVAR
                elsif ( $r =~ /^\w+$/ && $r !~ /^\d+$/ && $extra2 !~ /\'/ )
                {
                    if ( $r =~ /^([A-Z0-9_]+)$/ )
                    {
                        $r = qq{\$\_$r};
                        push @local_variables, $r
                            unless ( $local_variables{$r} );
                        $local_variables{$r} = 1;
                    }
                    else
                    {
                        $r = uc $r;
                        $r = qq{\$vals\{\'$r\'\}};
                    }
                }

                # treat everything else as String

#--- handle operator ---#
# inside if/switch case/[] statements, operator = is treated as comparison operator == instead of assignment operator =
                if ( $ifthenelse_flag eq $IF_STATE )
                {

                    # numeric comparison
                    $op =~ s/^=$/==/;

                    # string comparison
                    if ( $extra2 =~ /\'/g || ( $r =~ /^\'/ && $r =~ /\'$/ ) )
                    {
                        $state = $STR_STATE;
                        $op =~ s/^==\s*$/ eq /;
                        $op =~ s/^!=\s*$/ ne /;
                        $op =~ s/^>\s*$/ gt /;
                        $op =~ s/^>=\s*$/ ge /;
                        $op =~ s/^<\s*$/ lt /;
                        $op =~ s/^<=\s*$/ le /;
                    }
                    $state = $STR_END
                        if ( $r =~ /\'/g && $state eq $STR_STATE );
                }

# if operator = is an assignment operator, check the left hand side of the assignment, no special variables are allowed as LValues
                elsif ($op eq '='
                    && ( $l =~ /\$\_(m|n|w|v|r)\s*/ || $l =~ /^\$vals/ )
                    && $r =~ /\;\s*$/ )
                {
                    $error_report .=
                        qq{Syntax Error: variable $l is not a valid LValue for assignment\n};
                    return ( { error => '405', msg => $error_report } );
                }

                # handle string concat if operator is +;
                if (
                    (
                           $l =~ /\'$/
                        || $extra1 =~ /\'$/
                        || $r =~ /^\'/
                        || $extra2 =~ /^\'/
                    )
                    && $op =~ /\s*\+\s*/
                    )
                {
                    $op =~ s/\+/\./;
                }

                $s = qq{$l$extra1$op$extra2$r};
                $last_variable = $l if ($l);

                if ( length($r) )
                {

                    # clean last variable for expression
                    $last_variable = undef;
                }
                print qq{last variable3: $last_variable\n} if ( $debug == 1 );

            }

            # variable operator variable operator variable...
            elsif (
                ( split /(\+|\-|\*|\/|\*\*|\%|\,|>|>=|<|<=|=>|=|\!=)/, $s )
                > 0 )
            {
                print
                    'EXPR_STATE2: variable operator variable operator variable... <br />'
                    if ($debug);

                my @temp_list =
                    split /(\+|\-|\*|\/|\*\*|\%|\,|>|>=|<|<=|=>|=|\!=)/, $s;
                $s = undef;
                foreach my $element (@temp_list)
                {

                    # string end
                    if (   ( $element =~ /\'$/ && $state eq $STR_STATE )
                        || ( $element =~ /^\s*\'[^\']*\'$/ ) )
                    {
                        $state = $STR_END;

           # replace the operator from ==, !=, >, >=, <, <= to string operator
                        if ( $ifthenelse_flag eq $IF_STATE )
                        {
                            $s =~ s/==\s*$/ eq /g;
                            $s =~ s/!=\s*$/ ne /g;
                            $s =~ s/[^=]>\s*$/ gt /g;
                            $s =~ s/>=\s*$/ ge /g;
                            $s =~ s/<\s*$/ lt /g;
                            $s =~ s/<=\s*$/ le /g;
                        }

                        # handle string concat
                        if ( $element =~ /^\s*\'[^\']*\'$/ && $s =~ /\+\s*$/ )
                        {
                            $s =~ s/\+\s*$/\./;
                        }
                    }

                    # in the middle of a string
                    elsif ( $state eq $STR_STATE && $element !~ /\'/g )
                    {
                    }

                    # string start
                    elsif ( $element =~ /^\'/ )
                    {
                        $state = $STR_STATE;

                        # handle string concat
                        if ( $s =~ /\+\s*$/ )
                        {
                            $s =~ s/\+\s*$/\./;
                        }

                    }

                    # new: webservice variable |wspost|
                    elsif ( $element =~ /\s*\|wspost\|\s*/ )
                    {
                        $element =
                            qq{wspost('url'=>'tools/rc/$ws_info{filename}', 'mode'=>'$ws_info{mode}'};
                        $element .= qq{, 'alias'=>'$ws_info{alias}'}
                            if ( exists $ws_info{'alias'} );
                        $element .= qq{, 'dest'=>'$ws_info{dest}'}
                            if ( exists $ws_info{'dest'} );
                        $element .=
                            qq{, 'submit_only'=>'$ws_info{submit_only}'}
                            if ( exists $ws_info{'submit_only'} );
                        $element .= qq{, 'params'=>\\%vals)};
                    }

                    # special variables
                    elsif ( $element =~ /^\s*(m|n|t|v|w|r|g)\s*$/ )
                    {
                        $element = qq{\$\_$element};
                    }

                    # $vals{$x}
                    elsif ( $element =~ /^\s*x\s*$/ )
                    {
                        $element = qq{\$vals\{\$x\}};
                    }

                    # TRUE/FALSE keywords
                    elsif ( $element =~ /^\s*(true|false)\s*$/i )
                    {
                        $element =~ s/true/1/i;
                        $element =~ s/false/undef/i;
                    }

           # variables q3 pointer (REG.examdate), $vals{'FIELD'} or $_LOCALVAR
                    elsif ($element =~ /^\w+(\.[a-z][a-z0-9_]*)?$/
                        && $element !~ /^\d*\.?\d+$/ )
                    {

                        # local variables
                        if ( $element
                            =~ /^([A-Z][A-Z0-9_]*)\.([a-z][a-z0-9_]*)$/ )
                        {
                            $element = qq{\$\_$1\-\>\[0\]\{} . uc $2 . qq{\}};
                        }
                        elsif ( $element =~ /^([A-Z0-9_]+)$/ )
                        {
                            $element = qq{\$\_$element};
                            push @local_variables, $element
                                unless ( $local_variables{$element} );
                            $local_variables{$element} = 1;
                        }

                        # variables
                        else
                        {
                            $element = uc $element;
                            $element = qq{\$vals\{\'$element\'\}};
                        }
                    }
                    elsif ( $element eq '=' && $ifthenelse_flag eq $IF_STATE )
                    {
                        $element =~ s/=/==/ if ( $s !~ /[><!]\s*$/ );
                        $last_variable = undef;
                    }
                    $s .= $element;
                }

                # expression is not variable
                $last_variable = undef;

            }
            else
            {
                print 'EXPR_STATE3: other cases <br />' if ($debug);

                while ( $s =~ /\)/g )
                {
                    if ( $function_flag > 0 )
                    {
                        $function_flag--;
                    }

                }

                # expression is not variable
                $last_variable = undef;

            }

            if ( $state ne $STR_STATE )
            {
                if ( $s =~ /^(\w+)\(/ && $s !~ /\);?$/ )
                {
                    $function_flag++;
                    $state = $EXPR_STATE;
                }
                else
                {
                    $state = $EXPR_STATE;
                }

            }
        }

        # adding back head and tail to a list
        $s = $list_head . $s if ($list_head);
        $s .= $separator if ($separator);
        $s .= $list_tail if ($list_tail);
        $s .= ' '        if ( $state eq $STR_STATE );

        #--- pushing each word to the final output variable ---#
        $rangeprl .= qq{$s};

        # debug message
        print qq{$state: $s <br />} if ( $debug == 1 );

    }

# check for error, if any ] is missing from [[]] statement
#	if($customized_if_flag) {
#		$error_report = qq{Syntax Error: missing closing ] in the [[]] statement.\n};
#		return {error=>'405', msg=>$error_report};
#	}

    # remove trailing whitespaces from rangeprl
    $rangeprl =~ s/\s+$//;

    # check if it is the end of an else block, if so, then end the block
    $rangeprl .= ';}'
        if ( $ifthenelse_flag eq $ELSE_STATE
        || $ifthenelse_flag eq $THEN_STATE );

    #--- handle local variable ---#
    if (@local_variables)
    {
        foreach my $v (@local_variables)
        {

            # local variable
            $rangeprl = qq{my $v; $rangeprl};
        }
    }

    # append 1 in the end of the rangeval if contains []
    $rangeprl .= qq{1;} if ($contains_stack_flag);

    # escape html entity &notin; bug
    $rangeprl =~ s/\&notin/\& notin/;

    # final output
    # 	print qq{input: $input\n};
    # 	print qq{output: $rangeprl\n};
    #

    # debug

    return ( { error => '405', msg => $error_report } ) if ($error_report);
    return ( { result => '1', msg => $rangeprl } );
}

sub translate_rangecode_doc
{
    my $prot   = shift;
    my $switch = shift;
    my $dbc_o  = shift;
    my $input  = shift;
    my $tbl    = shift;
    my $fld    = shift;
    my $rangeprl;

    if ( $prot && $dbc_o )
    {
        my $translate_status =
            translate_rangecode( $prot, $dbc_o, $input, $tbl, $fld );
        $rangeprl = $translate_status->{msg};
        $rangeprl =~ s/([;]|\)\{)/$1<br \/>/g;
        $rangeprl =~ s/(\}\s*)(if|elsif|else)/$1<br \/>$2/ig;
        $rangeprl =~ s/\n\s+/\n/g;

    #debug: sendEmail('hqiu@ucsd.edu','hqiu@ucsd.edu','test range',$rangeprl);
        $rangeprl =
            qq{<p> Translation Result (perl): </p><table border="1"><tr><td><code>$rangeprl</code></td></tr></table>};
    }

    my $syntax_doc = q{
<div id="assumption" >

<h3>Assumptions</h3>
	<ul><li><b>NOTE:</b> In google spreadsheet when <b>rangeval is left to be blank</b>, the system assumes the following:

	<ul>
	<li>null value (n) is not allowed
		<ul><li>For checkbox group, at least one checkbox should be selected</li></ul>
   	</li>
	<li>if code is defined with the following sample syntaxes, rangeval will be validated against code
		<ul>
		<li>1=yes;0=no</li>
		<li>60..160</li>
		</ul>
	</li>
	<li>for any date field (type='D'), date will be validated, and no future date is allowed in the form</li>
	<li>if main question is answered, all of its subquestions (except type FILE) are required</li>
	<li>if main question is not answered, all of its subquestions (except type FILE) are required to be blank/null value</li> 
	</ul>
<h4>exceptions where null value is allowed:</h4>
	<ul>
	<li>for type file field (type='I'), allow everything including null value to pass</li>
	<li>for checkbox or radio button only contains one option, allow everything including null value to pass</li>
	<li>for all non-subquestion text input field (type='T', layout contains 'text', or 'paragraph;), allow everything including null value to pass</li>
	<li>if field is hidden, allow null value to pass
		<ul>
		<li>when visibleval is 'off', null value is always allowed</li>
		<li>when visibleval is 'off' conditionally, e.g. off(sc, bl), null value is allowed only on the visits defined in the condition</li>
		<li>when visibleval is 'on' conditionally, e.g. on(sc, bl), null value is allowed only on the visits other than the ones defined in the condition</li>
		</ul>
	</li>		
	<li>for log forms, if recno < 0, then allow null value to pass</li>
	<li>if field is a subquestion, it can be skipped (allow null value) by the following conditions:
		<ul>
		<li>if subquestion_trigger variable is defined in layout, and main question's answer is outside the range of subquestion_trigger</li>
		<li>or, if main question is a binary checkbox group or check box group, and none of the boxes is selected</li>
		<li>or, if main question is a numeric value and contains a negative value</li>
		<li>or, if main question is a non-numeric value and is not answered (value equals to n or m)</li>
		</ul>
	</li>
 	</ul>
 	</li></ul>
 	<br />
 	<ul><li><b>NOTE:</b>the above properties will be <b>overwritten when rangeval is defined.</b></li></ul>
  
</div>

<div id="expressions" >
<h3>Frequently used expressions</h3>
<table border="1" cellpadding="5">
<tr><th>rangeval  </th><th>  meaning </th></tr>
<tr><td> c </td><td> rangeval only allows values of defined in the code field, with the following format: value=display text;value2=display text 2; e.g. 0=No;1=Yes </td></tr>
<tr><td> n </td><td> rangeval only allows -4 (N/A, or blank) </td></tr>
<tr><td> m </td><td> rangeval only allows -1 (Missing) </td></tr>
<tr><td> true </td><td> rangeval allows everything </td></tr>
<tr><td> c, n </td><td> rangeval allows values defined in the code and blank </td></tr>
<tr><td> c, m </td><td> rangeval allows values defined in the code and missing </td></tr>
<tr><td> c, n, m </td><td> rangeval allows values defined in the code, blank and missing </td></tr>
</table>


</div>

<div id="rangeval_syntax" >

<h3> Rangeval Syntax </h3>
<ul>
  <li> Only <b>local variables or special variable t are allowed</b> on the left hand side of an assignment, e.g. A=1; t=1; </li>
  <li>Strings are quoted in single quotes ' </li>
  <li> Concatenation between two variables will require an empty string in between: e.g. a+' '+b </li>
  <li>2 usages of ";"
  	<ol>
    <li>Semicolons are used to end a variable assignment, e.g TEMP=1;</li>
    <li>separate multiple statements inside of if statement, e.g. if x>0 then TEMP=1; TEMP2=2; TEMP3=3; true else false</li>
    </ol>
  </li>
</ul>


<h4> Operators </h4>
<table border="1" cellpadding="5">
<tr><th> operator</th><th> usage </th><th>description </th><th> example </th></tr>
<tr><th> < </th><td> value 1 < value 2 </td><td> less than comparison </td><td>x < 1, x < 'z'  </td></tr>
<tr><th> <= </th><td> value 1 < = value 2 </td><td> less than or equal to comparison </td><td> x <= 1, x <= 'b'  </td></tr>
<tr><th> > </th><td> value 1 > value 2 </td><td> greater than comparison </td><td> x > 1, x > 'z'  </td></tr>
<tr><th> >= </th><td> value 1 >= value 2 </td><td> greater than or equal to comparison </td><td>x >= 1, x >= 'z'  </td></tr>
<tr><th> != </th><td> value 1 != value 2 </td><td> not equal comparison</td><td> x != 1 (x not equal to 1), examdate != 'IVR' (examdate not equal to 'IVR' ) </td></tr>
<tr><th> = </th><td> value 1 = value 2 </td><td> assignment [note: if = operator is used in an if-then-else statement's if condition, or switch statement's case condition, then the operator will be treated as an equal comparison operator] </td><td> A=1; (assigning numeric value "1" to local variable A), if x=1 then... (comparing whether x is equivalent to numeric value 1)  </td></tr>
<tr><th> .. </th><td> value 1 .. value 2 </td><td> range operator,used to define a set of discrete values between the endpoints provided (note: this operator can be used only inside an in statement) </td><td> 1..3 (1, 2, 3), 'a'..'c' ('a', 'b', 'c')  </td></tr>
<tr><th> +,-,*,/,% etc. </th><td> value 1 operator value 2 </td><td> mathematical operators </td><td>  </td></tr>
<tr><th> + </th><td> string+variable or variable+string or string+string </td><td> <b>string concatenation</b> </td><td> if length(x)>0 then true 
else 'Error Message: invalid x value, x='+x </td></tr>
</table>



<h4> Variables </h4>
<h5> Special Variables </h5>
<table border="1" cellpadding="5">
<tr><th> variable </th><th> meaning </th><th> perl translate </th></tr>
<tr><th> x </th><td> represents the current field value that the range code is checking </td><td>  $vals\{$x\} </td></tr>
<tr><th> m </th><td> Represents missing data code (BBL default value: -1) </td><td>  $_m </td></tr>
<tr><th> n </th><td> Represents not applicable code (BBL default value: -4) </td><td>  $_n </td></tr>
<tr><th> t </th><td> Represents track code </td><td>  $_t </td></tr>
<tr><th> v </th><td> RRepresents highest order visit initiated </td><td>  $_v </td></tr>
<tr><th> w </th><td> Represents evaluation mode (deprecated - code will always run in both form and master now) </td><td>  $_w </td></tr>
<tr><th> r </th><td> Represents enrollment date </td><td>  $_r </td></tr>
<tr><th> g </th><td> Represents enrollment group</td><td>  $_g </td></tr>
</table>


<h5> Barewords </h5>
Lowercase or mixed case barewords are interpreted as field variables. 
<br />
<ul>
  <li> Unless immediately followed by a parenthesis, in which case they are interpreted as function names; e.g. next_ptno();</li>
  <li>If followed by a curly brace {, they are interpreted as table names ([[#cross_form_checks|Cross from check]]). e.g. registry{};  </li>
</ul>

<h5> User Defined (Local) Variables </h5>
All <b>CAPITALIZED</b> barewords are interpreted as user defined local variables. e.g. A=5;

<h4> keywords </h4>
<table border="1" cellpadding="5">
<tr><th> keyword </th><th>usage</th><th> comment </th><th> example </th></tr>
<tr><th>  true </th><td> true </td><td>  represents value "1" </td><td>  A=true; or  if x>1 then true  </td></tr>
<tr><th>  false </th><td> false </td><td>  represents value "undef" </td><td>  A=false; or  if x>1 then true else false </td></tr>
<tr><th>  and </th><td> [variable] operator value **and** [variable] operator value </td><td>  if variable is not specified, it is then referred to x </td><td>  >=2007 and <=2010 (x is between 2007 and 2010)</td></tr>
<tr><th>  between ... and ...</th><td> [variable] **between** value **and** value </td><td>  if variable is not specified, it is then referred to x </td><td>   between 1 and 25  (x is a value between 1 and 25)  if rid between 100 and 105 then true  (checks whether field RID contains a value between 100 and 105) </td></tr>
<tr><th>  notbetween ... and ...</th><td> [variable] **notbetween** value **and** value </td><td>   if variable is not specified, it is then referred to x  </td><td>  notbetween 1 and 3   </td></tr>
<tr><th>  or </th><td> statement1 **or** statement2 </td><td>  if variable is not specified, it is then referred to x </td><td>  if x=2007 or x=2010 then true else false (checks whether the value of x is either 2007 or 2010)</td></tr>
<tr><th>  in </th><td> [variable] in(value1[, value 2, value 3...]) </td><td>  only numbers or strings or special variables (e.g. m, n, t ...) are recognized inside of the in statement, no quote is required around the strings.  If variable is not specified, then it is referred to x </td><td>   in(a..c)  value of x is 'a', 'b' or 'c' A in(1..5) checks if the value of local variable A is 1, 2, 3, 4 or 5 </td></tr>
<tr><th>  notin </th><td> [variable] notin(value1[, value 2, value 3...]) </td><td>  only numbers or strings or special variables (e.g. m, n, t ...) are recognized inside of the notin statement, no quote is required around the strings.  If variable is not specified, then it is referred to x </td><td>   notin(a..c)  value of x is not 'a', 'b' and 'c' A notin(1..5) checks if the value of local variable A is not 1, 2, 3, 4 and 5 </td></tr>
<tr><th>  endif, endswitch </th><td> </td><td>  end if / switch statements </td><td>   if x=1 then true endif switch x case m then true else false endswitch </td></tr>
</table>



<h4> Conditional Statements </h4>
<u><b>[condition:statement]</b></u>
<ul>
  <li> if ":statement" is defined (optional), rangeval will return statement if condition fulfilled.  
  	<ul><li>if condition not fulfilled, rangeval will return true </li>
   		<li>if ":statement" is not defined, rangeval will always return true</li>
   	</ul>	
  </li>  
  
  <li> [condition:statement] can be stacked together, if none of the conditions fulfilled, rangeval will return a true at the end of the stack
    <ul><li> stacked statements can be grouped using \{\} </li></ul>
  </li>
  
  <li> more examples
  	<ul>
    <li> conditionals can be join with "or" or "and" keyword</li>
    <li> statement can be variable, string, or a function call</li>
    </ul>
  </li>
</ul>

[x=n:'Error: please do not leave blank']<br />
[x notbetween 0 and 5:'Error: out of range. value of x:'+x]
<br />

or
<br />
[x notin (n,m):randomize(rid)]

<br /><br />
<br /><br />
<br /><br />

<u><b>if ... then ... [else ... ][endif]</b></u>
  <ul><li>if-then-else statement tells the rangeval to perform a block of rangeval code defined inside of "then" block or "else" block based on conditions from "if"</li></ul>
<table border="1" cellpadding="5">
<tr><th> block </th><th> rules</th><th> examples </th></tr>
<tr><td>if...</td><td> rangeval code defined in if block are usually comparison or range check statements, e.g. x > 1, x between 1 and 5, x = 'a' etc. Each comparison can be joined by an <b>and</b> or an <b>or</b> keyword; or grouped by parenthesis. e.g. x in (1..5) and (x != n or x != m) </td><td> TEMP=1; <br />
if TEMP in (1..5) and (x!=n or x!=m) <br />
then true <br />
else false <br /> </td></tr>
<tr><td> then...</td><td>  accepts true, false, numeric, string, variable assignment or function calls; multiple statements are separated by ";" </td><td>if length(x)!=0 
then t=1; randomize(rid);true 
else 'Error Message: Error!'   </td></tr>
<tr><td> else...</td><td> accepts true, false, numeric, string, variable assignment or function calls; multiple statements are separated by ";"</td><td> if length(x)=0
then 'Error Message: Error!'
else t=1; randomize(rid); true  </td></tr>
</table>


<ul><li> <b>NOTE:</b> if there're multiple if-then-else statements in the range code, use keyword <b>endif</b> to separate between two independent if-then-else statments</li></ul>
e.g.<br />

TEMP=1; <br />
if x > 0 then true else false <br />
endif<br />
if TEMP > x then true else false <br />

<br /><br />
<br /><br />
<br /><br />


<u><b>switch ... case ... then ... [else...][endswitch] </b></u>
<br /><br />
A conditional statement that is similar to if-then-else statement.  The purpose is to allow one variable to control the flow of each cases/conditions and to determine the final result. 
<br /><br />
Example:
<br /><br />

MM = randomize(rid);<br />
switch x<br />
case MM then true <br />
case length(rid) then true <br />
case 1 then true <br />
case 'abc' then true <br />
else 'Error Message: Error'<br />
The above code compares x against a local variable,function return value, number, and a string; if any of the cases is matching, then the check is true else displays an error message.  

<br />
<table border="1" cellpadding="5">
<tr><th> block </th><th> rules </th><th> examples </th></tr>
<tr><td> switch...</td><td> followed by a variable which is used to check against conditions defined in each case statement </td><td>  switch t <br />
case 1 then true <br />
case 2 then true <br />
else false  </td></tr>
<tr><td> case...</td><td>  a value used to check against switch variable.  The value could be a number, a string, a variable, or return value from a function call</td><td> case 1 then ...</td></tr>
</table>

<ul><li> <b>NOTE:</b> for multiple switch statements, use keyword "<b>endswitch</b>" to separate between the two statements. </li></ul>
e.g.<br />

switch x case m then true else false endswitch <br />
switch x case 1 then true <br />

<h4> Cross Form Checks </h4>
<h5> Pointer to A Form </h5>
<ul>
<li>
  Syntax: <b>tablename\{conditions\}</b>
  <ul>
    <li> tablename\{conditions}\ returns the matching record from form "tablename" with user specified "conditions" </li>
    <li> condition is <b>optional</b>, it defaults to match with the cross form's index field values ( e.g. rid and viscode for type 4) 
    	<ul>
		  <li> e.g. registry\{\} matches a record from registry table with the current check's rid and viscode value </li>
		  <li> e.g. registry\{viscode='sc'\} matches a record from registry table with current check's rid and screening visit </li>
		</ul>
    </li>  
    <li> condition always limit the sql query result to one record by automatically adding "<b>limit 1</b>" to the condition  </li>
    <li> condition always add "<b>entry=4</b>" for type 4 tables </li>
    <li> only <b>local variables will be interpolated</b> inside the user specified condition </li>
   </ul>
</li><li>        
	After assigning the form pointer to a local variable, e.g. REG=registry{};, you can reference field from the cross form with this syntax: LOCAL_VARIABLE.fieldname
	<ul><li> example: <br />
	
	REG=registry{}; <br />
	EI=REG.examinit; <br />
	</li></ul>
</li>
</ul>

<h4> Functions </h4>
  <ul><li><b>no keyword</b> (and, or, true, false, if, then, else ...) is allowed to be function names </li></ul>

<h5>is_numeric</h5>
<ul>
	<li>Test to determine if the value provided is a numeric value. Return 1 if value is numeric, 0 otherwise</li>
	<li>parameter: any value</li>
	<li>example: is_numeric(x)</li>
</ul>

<h5>is_zero</h5>
<ul>
	<li>Test to determine if the value provided is a zero. Return 1 if value is zero, 0 otherwise </li>
	<li>parameter: any value</li>
	<li>example: is_zero(x)</li>
</ul>
 
<h5> date_calc </h5>

<ul>
  <li> calculates: date + offset </li>
  <li> parameter: date (MM/DD/YYYY, if not specified, defaults to today's date), offset </li>
  <li> example 1: NEWDATE variable is assigned to 2 days before today's date <br />
NEWDATE = date_calc(offset=-2);</li>
  <li> example 2: can also be used with date_range_compare function <br />
if date_range_compare(date=x, lower_date=date_calc(date=randdate, offset=-2))  <br />
then true  <br />
else 'Error Message: x should be between 2 days prior to randdate, and today's date.'<br />
	</li>
</ul>

 
<h5> randomize </h5>
<ul>
  <li>needs to be activated for each project, projects where this function has been activated:
    <ul><li>adcs-igiv igiv</li></ul>
  </li>
  <li> randomizes one specific patient </li>
  <li> parameter: rid </li>
  <li> usage: <br />
randomize(rid) <br />
or<br />
TEMP=randomize(rid);<br /></li>
</ul>

<h5> next_ptno </h5>
<ul>
  <li> needs to be activated for each project, projects where this function has been activated:
    <ul>
    <li>adcs-dian dian</li>
    <li>adcs-igiv igiv</li>
    </ul>
  </li>
  <li> get next available patient screen number</li>
  <li> parameter: none </li>
  <li> usage:<br />
next_ptno()<br />
or <br />
TEMP=next_ptno(); <br />
  </li>
</ul>

<h5> ptno_push </h5>
<ul>
  <li> needs to be activated for each project, projects where this function has been activated:
    <ul><li> adcs-dian dian </li></ul>
  </li>
  <li> push dian id to a rest web service at washington university </li>
  <li> parameter: mode - inert, update </li>
  <li> usage: <br />
ptno_push(mode='i'); <br />
or <br />
ptno_push(mode='u'); <br />
  </li>
</ul>

<h5> index </h5>
<p>The index() function is used to determine the position of a letter or  
a substring in a string. For example, in the string '1:3:5' the letter  
'1' is in position 0, the '5' in position 4.</p>

index('1:3:5', '5') returns 4<br /><br />
index('1:3:5', '1') returns 0<br /><br />
index('1:3:5', '2') returns -1 (because 2 is not in the string)<br /><br />

<p>The index() function is usually used to check the sub-question logic  
when the main question type is a 'checkbox'.<br />
For example: if the main question is a checkbox field with 5 options  
(5=other). <br />
If '5=other' is checked, the subquestion has to be filled in,  
otherwise, the sub-question should be left blank. <br />
<br />

<p>Below is the code for the sub-question logic:</p>

<p>if index(main,'5')> -1 and length(x)>2 then true if index(x,'6')=-1  
and x=n then true else false</p>

<p>note: you can also reference perl doc on index() function</p>

<h5> return </h5>
<p>Exit from the range code.  return() function takes one parameter.  
<br /><br />
Below is the code for the return() function:
<br />
if x=1 then return(true)<br />
if x=m then return('Error Message: x should not be '+m)<br />
else return(false)<br />
</p>



<h5> date_validate </h5>
<ul>
<li>description: checks whether a date is valid or not</li>
<li>parameter: date (MM/DD/YYYY)</li>
<li>return values: method returns a 1 for valid date strings, undef otherwise</li>
<li>usage: <br />
date_validate(date='01/01/2009') <br />
</li>
</ul>

<h5> date_range_compare </h5>
<ul>
<li>description: checks whether a date is in the range by giving lower 
bound and upper bound dates. </li>
<li>parameter: date (MM/DD/YYYY), lower_date (MM/DD/YYYY), upper_date (MM/DD/YYYY)</li>
<li>return values: Method returns a scalar representing the results of 
evaluating whether a date falls within a date range (1 if date is 
within the range, 0 if the date is outside the range), undef otherwise.</li>
<li>usage: <br />
date_range_compare(date='02/02/2009', lower_date='02/02/2002', 
upper_date='02/02/2010') <br  />
</li>
</ul>


<h5> cdr_score </h5>
<ul>
<li>description: cdr score calculator</li>
<li>parameters: care, commun, home, judge, memory, orient</li>
<li>usage:  <br />
cdr_score(care=1, commun=1, home=1, judge=1, memory=1, orient=1) <br />
or <br />
cdr_score(care=care, commun=commun, home=home, judge=judge, memory=memory, orient=orient)<br />
</li>
</ul>
</div>


<div id="syntax_examples" >

<h3> Examples </h3>
<h5> #1 range check: using in statement </h5>
<table border="1" padding="4"><tr><td>in (0, 1, n, abc, a..c, 1..2)</td></tr></table>


<h5> #2 specify an error message (string concatenation (+) is used) <h5>
<table border="1" padding="4"><tr><td>
if x in (0, 1, n, abc, a..c, 1..2) <br /><br />
then true <br /><br />
else 'Error Message: x='+x+'is an incorrect value.'<br /><br />
</td></tr></table>

<h5> #3 range check: using between statement <h5>
<table border="1" padding="4"><tr><td>between -10 and 10</td></tr></table>

<h5> #4 specify an error message (string concatenation (+) is used) <h5>
<table border="1" padding="4"><tr><td>if x between -10 and 10 or x=m or x=n <br /><br />
then true <br /><br />
else 'Error Message: x='+x+' is an incorrect value.' <br /><br />
</td></tr></table>

<h5> #5 user defined local variables (all CAPS) assignment <h5>
<table border="1" padding="4"><tr><td>
TEMP1=length(x);<br /><br />
TEMP2=totscore;<br /><br />
if TEMP1>0 and TEMP2 between 10 and 20 <br /><br />
then randomize(rid); true <br /><br />
else false<br /><br />
</td></tr></table>

<h5> #6 [condition:statement] example <h5>
<table border="1" padding="4"><tr><td>[x=n:'Error: please do not leave the field blank!']</td></tr></table>


<h5> #7 switch statement <h5>
<table border="1" padding="4"><tr><td>switch x <br /><br />
case 1 then true <br /><br />
case 'abc' then true <br /><br />
case n then true <br /><br />
case length('abc') then true <br /><br />
</td></tr></table>

<h5> #8 if statement, and usage of keyword "endif" and function return() <h5>
<table border="1" padding="4"><tr><td>if x=1 <br /><br />
then return(true) <br /><br />
if x='abc' <br /><br />
then return(true) <br /><br />
endif <br /><br />
if x=n <br /><br />
then true <br /><br /> 
if x=length('abc') <br /><br />
then true<br /><br />
</td></tr></table>

<h5> #9 grouping [condition:statment]using { } <h5>
<table border="1" padding="4"><tr><td>
{[x=n:'Error: do not leave blank.']
<br /><br />
[x notbetween 0 and 20:'Error: out of range.']
<br /><br />
[RES != 1:'Error: function next_ptno() failed.']}
<br /><br />
RES=next_ptno();
<br /><br />
</td></tr></table> 

<h5> #10 cross form check: auto populating key indexes in the sql condition <h5>
<table border="1" padding="4"><tr><td>
REG2=registry{examinit='a b c' and id>0};  <br /><br />
</td></tr></table>

<h5> #11 cross form check: override default auto populated condition <h5>
<table border="1" padding="4"><tr><td>
REG2=registry{examinit='a b c' and id>0 and rid is not null and viscode is not null};  <br /><br />
</td></tr></table>
</div>

		
	};
    my $html = <<__HTML__;
	
			<div id="intro">
				<div id="pageHeader">
					<h1><span>Range Code Translate</span></h1>
					<h2><span>Welcome</span></h2>
				</div>

				<div id="quickStart">
					<p class="p1">tools/range_translate is a BBL tool used to translate rangeval to perl code.<br />
					Rangeval is used in Google Docs data dictionary spreadsheet for Quality Assurance(QA) checking. 
					Rangeval is expressed in an English like programming language to ease the effort of code writing for end-users.
				</div>	       			
			</div>    

	    <li class="plus"><a href="javascript:unhide('details');"><img src="/icons/addins/plus.png">Instructions</a></li>

		<div id="details" class="hidden"> 
		
			<div id="basics">
				<h3><span>Required Parameter</h3>
				<ul><li>none</li></ul>
				<h3><span>Optional Parameter</h3>
				<ul>
					<li><span><b class="b1">prot:</b> protocol Initial e.g. bblmisc6; required only when rangeval is reference to database, e.g. registry{} </span></li>
					<li><span><b class="b2">db:</b> database connection (switch): adcs, cfar, spotrias_cuffs, igiv etc; required only when rangeval is reference to database, e.g. registry{} </span></li>				
					<li><span><b class="b3">input:</b> rangeval code </span></li>
					<li><span><b class="b3">tbl:</b> optional, tablename </span></li>
					<li><span><b class="b3">fld:</b> optional, fieldname </span></li>
					<li><span><b class="b1">debug:</b>debug mode flag</span></li>
				</ul>
			</div>
			
			<div id="sample">
				<h3> Sample Links </h3>
				<ul>
					<li><a href="https://svetlana.ucsd.edu/tools/range_translate?prot=igiv&db=igiv" target="_blank">https://svetlana.ucsd.edu/tools/range_translate?prot=igiv&db=igiv</a></li>
					<li><a href="https://svetlana.ucsd.edu/tools/range_translate?prot=ngf&db=adcs_ngf" target="_blank">https://svetlana.ucsd.edu/tools/range_translate?prot=ngf&db=adcs_ngf</a></li>
				</ul>
			</div>
		</div>
	    <li class="plus"><a href="javascript:unhide('syntax');"><img src="/icons/addins/plus.png">Rangeval Syntax</a></li>
		<div id="syntax" class="hidden">
			$syntax_doc
		</div>
			<div id="test">
				<h3><span>Test Range Code Translator</h3>

__HTML__

    $html .= qq{				
				<form name="test" action="" method="get">
					<table border="0">
					<tr><td>project: </td><td><input type="text" name="prot" value="$prot" ></td></tr>
					<tr><td>database: </td><td><input type="text" name="db" value="$switch" ></input></td></tr>
					<tr><td>table: </td><td><input type="text" name="tbl" value="$tbl" ></input></td></tr>
					<tr><td>field: </td><td><input type="text" name="fld" value="$fld" ></input></td></tr>
					</table>
					<p class="p1">In the following input box, type a valid range code and click "Translate"</p>				
					<textarea name="input" cols="40" rows="5" >$input</textarea>
					
					<br />
					<input type="submit" value="Translate"/>
				</form>
				<br />
				$rangeprl
			</div>

	};
    return $html;
}

1;

