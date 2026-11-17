       >>source free
identification division.
program-id. oracle-bridge.
environment division.
input-output section.
file-control.
copy "selsys.cob".
copy "selanal.cob".
copy "selpl.cob".
select seed-file assign "seed.txt" organization line sequential.
select dump-file assign "dump.txt" organization line sequential.
data division.
file section.
copy "fdsys.cob".
copy "fdanal.cob".
copy "fdpl.cob".
fd seed-file.
01 seed-line pic x(200).
fd dump-file.
01 dump-line pic x(200).
working-storage section.
copy "wsnames.cob".
01 purchase-path.
copy "file22.cob".
copy "wscall.cob".
01 fs-reply pic xx.
01 rrn binary-long unsigned.
01 mode-name pic x(8).
01 kind pic x.
01 eof-flag binary-char value 0.
01 gl-text pic 9(6).
01 fixed-date pic x(10) value "02/01/2020".
procedure division.
    accept mode-name from command-line
    evaluate function trim(mode-name)
      when "seed" perform seed-data
      when "dump" perform dump-data
      when "run"
        open input system-file
        perform check-status
        move 1 to rrn
        read system-file
        perform check-status
        close system-file
        call "sl070" using ws-calling-data system-record
                           fixed-date file-defs
      when other move 2 to return-code goback
    end-evaluate
    move 0 to return-code
    goback.
check-status.
    if fs-reply not = "00"
      display "Oracle file error: " fs-reply upon syserr
      move 1 to return-code
      stop run
    end-if.
seed-data.
    initialize system-record
    move "Oracle Company" to usera
    move 1 to scycle file-status(15) file-status(22)
    move 6 to op-system
    move 60 to page-lines
    move 3 to date-form
    open output system-file
    perform check-status
    move 1 to rrn
    write system-record
    perform check-status
    close system-file
    open output analysis-file
    perform check-status
    open output purchase-file
    perform check-status
    open input seed-file
    perform until eof-flag = 1
      read seed-file at end move 1 to eof-flag
        not at end
          move seed-line(1:1) to kind
          evaluate kind
            when "A"
              initialize analysis-record
              unstring seed-line delimited by "|" into kind
                pa-system pa-group gl-text pa-desc pa-print
              end-unstring
              move gl-text to pa-gl
              write analysis-record
              perform check-status
            when "P"
              initialize purch-record
              unstring seed-line delimited by "|" into kind
                purch-key purch-name
              end-unstring
              move 1 to purch-status
              write purch-record
              perform check-status
            when other
              move 2 to return-code stop run
          end-evaluate
      end-read
    end-perform
    close seed-file analysis-file purchase-file.
dump-data.
    open output dump-file
    open input analysis-file
    perform check-status
    perform until eof-flag = 1
      read analysis-file next record
        at end move 1 to eof-flag
        not at end
          perform check-status
          move spaces to dump-line
          move pa-gl to gl-text
          string "A|" pa-system "|" pa-group "|" gl-text "|"
            function trim(pa-desc) "|" function trim(pa-print)
            into dump-line
          end-string
          write dump-line
      end-read
    end-perform
    close analysis-file
    move 0 to eof-flag
    open input purchase-file
    perform check-status
    perform until eof-flag = 1
      read purchase-file next record
        at end move 1 to eof-flag
        not at end
          perform check-status
          move spaces to dump-line
          string "P|" purch-key "|" function trim(purch-name)
            into dump-line
          end-string
          write dump-line
      end-read
    end-perform
    close purchase-file dump-file.
