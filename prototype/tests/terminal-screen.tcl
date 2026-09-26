proc cmdabc_screen_put {lines_name row col char} {
  upvar 1 $lines_name lines

  while {[llength $lines] <= $row} {
    lappend lines ""
  }
  set line [lindex $lines $row]
  set length [string length $line]
  if {$col > $length} {
    append line [string repeat " " [expr {$col - $length}]]
  }
  if {$col == [string length $line]} {
    append line $char
  } else {
    set line [string replace $line $col $col $char]
  }
  lset lines $row $line
}

proc cmdabc_screen_csi {lines_name row_name col_name sequence} {
  upvar 1 $lines_name lines $row_name row $col_name col

  set final [string index $sequence end]
  set params [string range $sequence 0 end-1]
  set private [string match {\?*} $params]
  if {$private} {
    return
  }
  set first [lindex [split $params ";"] 0]
  if {$first eq "" || ![string is integer -strict $first]} {
    set first 1
  }

  switch -- $final {
    A {
      set row [expr {max(0, $row - $first)}]
    }
    B {
      set row [expr {$row + $first}]
      while {[llength $lines] <= $row} {
        lappend lines ""
      }
    }
    C {
      set col [expr {$col + $first}]
    }
    D {
      set col [expr {max(0, $col - $first)}]
    }
    G {
      set col [expr {max(0, $first - 1)}]
    }
    H - f {
      set parts [split $params ";"]
      set wanted_row [lindex $parts 0]
      set wanted_col [lindex $parts 1]
      if {$wanted_row eq "" || ![string is integer -strict $wanted_row]} {
        set wanted_row 1
      }
      if {$wanted_col eq "" || ![string is integer -strict $wanted_col]} {
        set wanted_col 1
      }
      set row [expr {max(0, $wanted_row - 1)}]
      set col [expr {max(0, $wanted_col - 1)}]
      while {[llength $lines] <= $row} {
        lappend lines ""
      }
    }
    K {
      while {[llength $lines] <= $row} {
        lappend lines ""
      }
      set line [lindex $lines $row]
      set mode 0
      if {[string is integer -strict $params]} {
        set mode $params
      }
      if {$mode == 2} {
        set line ""
      } elseif {$mode == 1} {
        if {$col < [string length $line]} {
          set line "[string repeat " " [expr {$col + 1}]][string range $line [expr {$col + 1}] end]"
        } else {
          set line ""
        }
      } elseif {$col < [string length $line]} {
        set line [string range $line 0 [expr {$col - 1}]]
      }
      lset lines $row $line
    }
  }
}

proc cmdabc_render_terminal_tail {initial_line data} {
  set lines [list $initial_line]
  set row 0
  set col [string length $initial_line]
  set state normal
  set csi ""

  for {set index 0} {$index < [string length $data]} {incr index} {
    set char [string index $data $index]
    if {$state eq "escape"} {
      if {$char eq "\["} {
        set state csi
        set csi ""
      } else {
        set state normal
      }
      continue
    }
    if {$state eq "csi"} {
      append csi $char
      scan $char %c code
      if {$code >= 64 && $code <= 126} {
        cmdabc_screen_csi lines row col $csi
        set state normal
      }
      continue
    }

    switch -- $char {
      "\033" {
        set state escape
      }
      "\r" {
        set col 0
      }
      "\n" {
        incr row
        while {[llength $lines] <= $row} {
          lappend lines ""
        }
      }
      "\b" {
        set col [expr {max(0, $col - 1)}]
      }
      "\t" {
        set col [expr {(($col / 8) + 1) * 8}]
      }
      default {
        scan $char %c code
        if {$code >= 32 && $code != 127} {
          cmdabc_screen_put lines $row $col $char
          incr col
        }
      }
    }
  }

  set visible {}
  foreach line $lines {
    set line [string trimright $line]
    if {$line ne ""} {
      lappend visible $line
    }
  }
  return $visible
}

proc cmdabc_assert_stable_screen {initial_line expected} {
  set saved_timeout $::timeout
  set ::timeout 1
  set tail ""
  expect {
    -re {.+} {
      append tail $expect_out(buffer)
      exp_continue
    }
    timeout {}
    eof {
      puts stderr "FAIL: shell exited before the success screen became stable"
      exit 1
    }
  }
  set ::timeout $saved_timeout

  set visible [cmdabc_render_terminal_tail $initial_line $tail]
  if {$visible ne $expected} {
    binary scan $tail H* tail_hex
    puts stderr "FAIL: final terminal screen does not match the expected stable state"
    puts stderr "expected: <$expected>"
    puts stderr "actual:   <$visible>"
    puts stderr "tail hex: <$tail_hex>"
    exit 1
  }
}

proc cmdabc_assert_stable_success_screen {initial_line success prompt} {
  cmdabc_assert_stable_screen $initial_line \
    [list [string trimright $success] [string trimright $prompt]]
}
