CLASS zcl_run_class DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    TYPES: BEGIN OF ty_param_input,
             selname TYPE rsparams-selname,
             kind    TYPE rsparams-kind,
             sign    TYPE rsparams-sign,
             option  TYPE rsparams-option,
             low     TYPE string,
             high    TYPE string,
           END OF ty_param_input,
           tt_param_input TYPE STANDARD TABLE OF ty_param_input WITH EMPTY KEY.

    TYPES: BEGIN OF ty_run_result,
             success TYPE abap_bool,
             message TYPE string,
             lines   TYPE i,
             data    TYPE REF TO data,
           END OF ty_run_result.

    METHODS run_payload
      IMPORTING iv_payload       TYPE string
      RETURNING VALUE(rs_result) TYPE ty_run_result.

    METHODS parse_payload
      IMPORTING iv_payload TYPE string
      EXPORTING ev_report  TYPE program
                ev_variant TYPE variant
                et_input   TYPE tt_param_input
                ev_message TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    METHODS build_request
      IMPORTING iv_payload TYPE string
      EXPORTING ev_report  TYPE program
                ev_variant TYPE variant
                et_params  TYPE rsparams_tt
                ev_message TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_run_request,
             report  TYPE string,
             variant TYPE string,
             params  TYPE tt_param_input,
           END OF ty_run_request.

    TYPES: BEGIN OF ty_seldef,
             name       TYPE rsparams-selname,
             kind       TYPE rsparams-kind,
             obligatory TYPE abap_bool,
             rollname   TYPE rollname,
             convexit   TYPE dd01l-convexit,
             default    TYPE string,
           END OF ty_seldef,
           tt_seldef TYPE HASHED TABLE OF ty_seldef WITH UNIQUE KEY name.

    TYPES: BEGIN OF ty_symbol,
             name      TYPE string,
             rollname  TYPE rollname,
             tabname   TYPE tabname,
             fieldname TYPE fieldname,
           END OF ty_symbol,
           tt_symbol TYPE HASHED TABLE OF ty_symbol WITH UNIQUE KEY name.

    TYPES: BEGIN OF ty_outtab,
             cond_field TYPE string,
             when_true  TYPE abap_bool,
             tabname    TYPE string,
           END OF ty_outtab,
           tt_outtab TYPE STANDARD TABLE OF ty_outtab WITH EMPTY KEY.

    TYPES: BEGIN OF ty_meta,
             rollname TYPE rollname,
             convexit TYPE dd01l-convexit,
           END OF ty_meta.

    DATA mv_report     TYPE program.
    DATA mt_seldef     TYPE tt_seldef.
    DATA mt_stmt       TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA mv_loader     TYPE formname.
    DATA mt_data_forms TYPE STANDARD TABLE OF formname WITH EMPTY KEY.
    DATA mt_outtabs    TYPE tt_outtab.

    METHODS load_payload
      IMPORTING io_out            TYPE REF TO if_oo_adt_classrun_out
      RETURNING VALUE(rv_payload) TYPE string.

    METHODS analyze_program
      IMPORTING iv_report  TYPE program
      RETURNING VALUE(rv_message) TYPE string.

    METHODS read_lines
      IMPORTING iv_report TYPE program
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS to_internal
      IMPORTING iv_value          TYPE string
                iv_rollname       TYPE rollname
                iv_convexit       TYPE dd01l-convexit
      RETURNING VALUE(rv_value)   TYPE string.

    METHODS resolve_meta
      IMPORTING iv_ref          TYPE string
                it_symbol       TYPE tt_symbol
      RETURNING VALUE(rs_meta)  TYPE ty_meta.

    METHODS load_variant
      IMPORTING iv_report  TYPE program
                iv_variant TYPE variant
      EXPORTING et_params  TYPE rsparams_tt
                ev_message TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    METHODS execute_report
      IMPORTING it_params        TYPE rsparams_tt
      RETURNING VALUE(rs_result) TYPE ty_run_result.

    METHODS apply_selection
      IMPORTING it_params        TYPE rsparams_tt
      RETURNING VALUE(rv_message) TYPE string.

    METHODS tokens_of
      IMPORTING iv_stmt        TYPE string
      RETURNING VALUE(rt_tok)  TYPE string_table.

ENDCLASS.


CLASS zcl_run_class IMPLEMENTATION.

  METHOD run_payload.
    DATA lt_params  TYPE rsparams_tt.
    DATA lv_report  TYPE program.
    DATA lv_variant TYPE variant.
    DATA lv_message TYPE string.

    IF build_request( EXPORTING iv_payload = iv_payload
                      IMPORTING ev_report  = lv_report
                                ev_variant = lv_variant
                                et_params  = lt_params
                                ev_message = lv_message ) = abap_false.
      rs_result-message = lv_message.
      RETURN.
    ENDIF.

    rs_result = execute_report( lt_params ).
  ENDMETHOD.


  METHOD if_oo_adt_classrun~main.
    DATA(lv_payload) = load_payload( out ).
    IF lv_payload IS INITIAL.
      out->write( '输入为空。请跑 ABAP Unit，或在同一会话把 JSON 写入 MEMORY ID ZADT_RUN_REQ。' ).
      RETURN.
    ENDIF.

    DATA(ls_result) = run_payload( lv_payload ).
    out->write( ls_result-message ).
    IF ls_result-data IS BOUND.
      ASSIGN ls_result-data->* TO FIELD-SYMBOL(<lt_rows>).
      IF sy-subrc = 0.
        out->write( <lt_rows> ).
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD load_payload.
    IMPORT req_json = rv_payload FROM MEMORY ID 'ZADT_RUN_REQ'.
    IF rv_payload IS NOT INITIAL.
      FREE MEMORY ID 'ZADT_RUN_REQ'.
      io_out->write( '已从 ABAP MEMORY ID ZADT_RUN_REQ 读到请求。' ).
    ENDIF.
  ENDMETHOD.


  METHOD parse_payload.
    DATA ls_req TYPE ty_run_request.

    CLEAR: ev_report, ev_variant, et_input, ev_message.

    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json = iv_payload
                                   CHANGING  data = ls_req ).
      CATCH cx_root INTO DATA(lx_json).
        ev_message = |JSON 解析失败: { lx_json->get_text( ) }|.
        RETURN.
    ENDTRY.

    ev_report  = to_upper( condense( ls_req-report ) ).
    ev_variant = to_upper( condense( ls_req-variant ) ).
    et_input   = ls_req-params.

    IF ev_report IS INITIAL.
      ev_message = 'JSON 中没有报表名 report。'.
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD build_request.
    DATA lt_input   TYPE tt_param_input.
    DATA lt_variant TYPE rsparams_tt.
    DATA ls_param   TYPE rsparams.
    DATA ls_def     TYPE ty_seldef.
    DATA ls_in      TYPE ty_param_input.
    DATA lv_missing TYPE string.

    CLEAR: ev_report, ev_variant, et_params, ev_message,
           mt_seldef, mt_stmt, mt_data_forms, mt_outtabs, mv_loader.

    IF parse_payload( EXPORTING iv_payload = iv_payload
                      IMPORTING ev_report  = ev_report
                                ev_variant = ev_variant
                                et_input   = lt_input
                                ev_message = ev_message ) = abap_false.
      RETURN.
    ENDIF.

    SELECT SINGLE @abap_true FROM trdir WHERE name = @ev_report INTO @DATA(lv_exists).
    IF sy-subrc <> 0.
      ev_message = |报表 { ev_report } 不存在。|.
      RETURN.
    ENDIF.

    ev_message = analyze_program( ev_report ).
    IF ev_message IS NOT INITIAL.
      RETURN.
    ENDIF.

    IF ev_variant IS NOT INITIAL.
      IF load_variant( EXPORTING iv_report  = ev_report
                                 iv_variant = ev_variant
                       IMPORTING et_params  = lt_variant
                                 ev_message = ev_message ) = abap_false.
        RETURN.
      ENDIF.
      et_params = lt_variant.
    ENDIF.

    LOOP AT lt_input INTO ls_in.
      CLEAR ls_param.
      ls_param-selname = to_upper( condense( ls_in-selname ) ).
      IF ls_param-selname IS INITIAL.
        CONTINUE.
      ENDIF.

      CLEAR ls_def.
      READ TABLE mt_seldef INTO ls_def WITH TABLE KEY name = ls_param-selname.
      IF ls_def-kind IS NOT INITIAL.
        ls_param-kind = ls_def-kind.
      ELSEIF ls_in-kind IS NOT INITIAL.
        ls_param-kind = to_upper( condense( ls_in-kind ) ).
      ELSEIF ls_param-selname CP 'S_*'.
        ls_param-kind = 'S'.
      ELSE.
        ls_param-kind = 'P'.
      ENDIF.

      ls_param-sign   = COND #( WHEN ls_in-sign IS INITIAL THEN 'I' ELSE to_upper( ls_in-sign ) ).
      ls_param-option = COND #( WHEN ls_in-option IS INITIAL THEN 'EQ' ELSE to_upper( ls_in-option ) ).
      ls_param-low    = to_internal( iv_value    = ls_in-low
                                     iv_rollname = ls_def-rollname
                                     iv_convexit = ls_def-convexit ).
      ls_param-high   = to_internal( iv_value    = ls_in-high
                                     iv_rollname = ls_def-rollname
                                     iv_convexit = ls_def-convexit ).

      DELETE et_params WHERE selname = ls_param-selname.
      APPEND ls_param TO et_params.
    ENDLOOP.

    LOOP AT mt_seldef INTO ls_def WHERE kind = 'P' AND default <> ''.
      READ TABLE et_params TRANSPORTING NO FIELDS WITH KEY selname = ls_def-name.
      IF sy-subrc <> 0.
        CLEAR ls_param.
        ls_param-selname = ls_def-name.
        ls_param-kind    = 'P'.
        ls_param-sign    = 'I'.
        ls_param-option  = 'EQ'.
        ls_param-low     = ls_def-default.
        APPEND ls_param TO et_params.
      ENDIF.
    ENDLOOP.

    LOOP AT mt_seldef INTO ls_def WHERE obligatory = abap_true.
      READ TABLE et_params TRANSPORTING NO FIELDS WITH KEY selname = ls_def-name.
      IF sy-subrc <> 0.
        lv_missing = COND #( WHEN lv_missing IS INITIAL THEN ls_def-name
                             ELSE |{ lv_missing }, { ls_def-name }| ).
      ENDIF.
    ENDLOOP.
    IF lv_missing IS NOT INITIAL.
      ev_message = |缺少必输字段: { lv_missing }。|.
      RETURN.
    ENDIF.

    CLEAR ev_message.
    rv_ok = abap_true.
  ENDMETHOD.


  METHOD analyze_program.
    DATA lt_symbol       TYPE tt_symbol.
    DATA lt_plain        TYPE STANDARD TABLE OF formname WITH EMPTY KEY.
    DATA lt_performed    TYPE STANDARD TABLE OF formname WITH EMPTY KEY.
    DATA lt_info         TYPE STANDARD TABLE OF selinfo WITH EMPTY KEY.
    DATA lt_tok          TYPE string_table.
    DATA lv_in_form      TYPE abap_bool.
    DATA lv_in_start     TYPE abap_bool.
    DATA lv_form         TYPE formname.
    DATA lv_display_form TYPE formname.
    DATA lv_cond         TYPE string.
    DATA lv_when_true    TYPE abap_bool.
    DATA lv_buf          TYPE string.
    DATA lv_line         TYPE string.
    DATA lv_rest         TYPE string.
    DATA lv_name         TYPE rsparams-selname.
    DATA lv_sel          TYPE rsparams-selname.
    DATA lv_called       TYPE formname.
    DATA lv_type         TYPE string.
    DATA lv_def          TYPE string.
    DATA lv_idx          TYPE i.
    DATA lv_out_idx      TYPE i.
    DATA ls_meta         TYPE ty_meta.
    DATA ls_info         TYPE selinfo.
    DATA lv_stmt         TYPE string.
    DATA lv_perf         TYPE formname.
    DATA lv_plain        TYPE formname.
    FIELD-SYMBOLS <def>  TYPE ty_seldef.

    mv_report = iv_report.
    CLEAR: mt_seldef, mt_stmt, mt_data_forms, mt_outtabs, mv_loader.

    DATA(lt_lines) = read_lines( iv_report ).
    IF lt_lines IS INITIAL.
      rv_message = |读不到报表 { iv_report } 的源码。|.
      RETURN.
    ENDIF.

    LOOP AT lt_lines INTO DATA(lv_raw).
      lv_line = condense( lv_raw ).
      IF lv_line IS INITIAL OR lv_line(1) = '*'.
        CONTINUE.
      ENDIF.
      IF lv_line CS '"'.
        SPLIT lv_line AT '"' INTO lv_line lv_rest.
        lv_line = condense( lv_line ).
      ENDIF.
      IF lv_line IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_buf = COND #( WHEN lv_buf IS INITIAL THEN lv_line ELSE |{ lv_buf } { lv_line }| ).
      IF lv_line CS '.'.
        APPEND to_upper( lv_buf ) TO mt_stmt.
        CLEAR lv_buf.
      ENDIF.
    ENDLOOP.

    CALL FUNCTION 'RS_SELECTIONS_DESCRIPTION'
      EXPORTING
        report              = iv_report
      TABLES
        selections_info     = lt_info
      EXCEPTIONS
        no_selections       = 1
        report_not_existent = 2
        subroutine_pool     = 3
        OTHERS              = 4.
    IF sy-subrc = 0.
      LOOP AT lt_info INTO ls_info WHERE kind = 'P' OR kind = 'S'.
        lv_name = condense( ls_info-name ).
        IF lv_name IS INITIAL OR line_exists( mt_seldef[ name = lv_name ] ).
          CONTINUE.
        ENDIF.
        INSERT VALUE #( name       = lv_name
                        kind       = ls_info-kind
                        obligatory = COND #( WHEN ls_info-obligatory = abap_true THEN abap_true ) )
               INTO TABLE mt_seldef.
      ENDLOOP.
    ENDIF.

    LOOP AT mt_stmt INTO lv_stmt.
      lt_tok = tokens_of( lv_stmt ).
      IF lt_tok IS INITIAL.
        CONTINUE.
      ENDIF.

      CASE lt_tok[ 1 ].
        WHEN 'FORM'.
          lv_in_form  = abap_true.
          lv_in_start = abap_false.
          CLEAR: lv_cond, lv_when_true.
          IF lines( lt_tok ) >= 2.
            lv_form = lt_tok[ 2 ].
            IF NOT line_exists( lt_tok[ table_line = 'USING' ] )
               AND NOT line_exists( lt_tok[ table_line = 'CHANGING' ] )
               AND NOT line_exists( lt_tok[ table_line = 'TABLES' ] )
               AND NOT line_exists( lt_tok[ table_line = 'RAISING' ] ).
              APPEND lv_form TO lt_plain.
            ENDIF.
          ENDIF.

        WHEN 'ENDFORM'.
          CLEAR: lv_in_form, lv_form, lv_cond, lv_when_true.

        WHEN 'START-OF-SELECTION'.
          lv_in_start = abap_true.

        WHEN 'END-OF-SELECTION' OR 'INITIALIZATION' OR 'TOP-OF-PAGE' OR 'END-OF-PAGE'.
          CLEAR lv_in_start.

        WHEN 'ENDIF'.
          CLEAR: lv_cond, lv_when_true.

        WHEN 'ELSE'.
          lv_when_true = abap_false.

        WHEN 'IF'.
          IF line_exists( lt_tok[ table_line = 'ABAP_TRUE' ] ) AND lines( lt_tok ) >= 2.
            lv_cond      = lt_tok[ 2 ].
            lv_when_true = abap_true.
          ENDIF.

        WHEN 'PERFORM'.
          IF lv_in_start = abap_true
             AND lines( lt_tok ) >= 2
             AND NOT line_exists( lt_tok[ table_line = 'USING' ] )
             AND NOT line_exists( lt_tok[ table_line = 'CHANGING' ] )
             AND NOT line_exists( lt_tok[ table_line = 'TABLES' ] ).
            lv_called = lt_tok[ 2 ].
            IF NOT line_exists( lt_performed[ table_line = lv_called ] ).
              APPEND lv_called TO lt_performed.
            ENDIF.
          ENDIF.

        WHEN 'DATA' OR 'STATICS'.
          IF lv_in_form = abap_false AND lines( lt_tok ) >= 4 AND lt_tok[ 3 ] = 'TYPE'.
            lv_type = lt_tok[ 4 ].
            IF lv_type NP 'STANDARD*' AND lv_type NP 'SORTED*' AND lv_type NP 'HASHED*'
               AND lv_type <> 'TABLE' AND lv_type <> 'REF' AND lv_type <> 'RANGE'
               AND lv_type NS '=>'
               AND NOT line_exists( lt_symbol[ name = lt_tok[ 2 ] ] ).
              INSERT VALUE #( name = lt_tok[ 2 ] rollname = lv_type ) INTO TABLE lt_symbol.
            ENDIF.
          ENDIF.

        WHEN 'SELECT-OPTIONS' OR 'PARAMETERS'.
          IF lines( lt_tok ) < 2.
            CONTINUE.
          ENDIF.
          lv_sel = lt_tok[ 2 ].
          READ TABLE mt_seldef ASSIGNING <def> WITH TABLE KEY name = lv_sel.
          IF sy-subrc <> 0.
            INSERT VALUE #( name = lv_sel
                            kind = COND #( WHEN lt_tok[ 1 ] = 'SELECT-OPTIONS' THEN 'S' ELSE 'P' ) )
                   INTO TABLE mt_seldef ASSIGNING <def>.
          ELSEIF <def>-kind IS INITIAL.
            <def>-kind = COND #( WHEN lt_tok[ 1 ] = 'SELECT-OPTIONS' THEN 'S' ELSE 'P' ).
          ENDIF.
          IF line_exists( lt_tok[ table_line = 'OBLIGATORY' ] ).
            <def>-obligatory = abap_true.
          ENDIF.

          IF lt_tok[ 1 ] = 'SELECT-OPTIONS'.
            READ TABLE lt_tok WITH KEY table_line = 'FOR' TRANSPORTING NO FIELDS.
            lv_idx = sy-tabix.
            IF sy-subrc = 0 AND lv_idx < lines( lt_tok ).
              ls_meta = resolve_meta( iv_ref = lt_tok[ lv_idx + 1 ] it_symbol = lt_symbol ).
              <def>-rollname = ls_meta-rollname.
              <def>-convexit = ls_meta-convexit.
            ENDIF.
          ELSE.
            READ TABLE lt_tok WITH KEY table_line = 'DEFAULT' TRANSPORTING NO FIELDS.
            lv_idx = sy-tabix.
            IF sy-subrc = 0 AND lv_idx < lines( lt_tok ).
              lv_def = lt_tok[ lv_idx + 1 ].
              IF strlen( lv_def ) >= 2 AND lv_def(1) = ''''.
                lv_def = substring( val = lv_def off = 1 len = strlen( lv_def ) - 2 ).
              ENDIF.
              <def>-default = lv_def.
            ENDIF.
          ENDIF.

      ENDCASE.

      IF lv_stmt CS 'REUSE_ALV_GRID_DISPLAY' AND lv_form IS NOT INITIAL.
        lv_display_form = lv_form.
        READ TABLE lt_tok WITH KEY table_line = 'T_OUTTAB' TRANSPORTING NO FIELDS.
        lv_out_idx = sy-tabix.
        IF sy-subrc = 0 AND lv_out_idx + 2 <= lines( lt_tok ) AND lt_tok[ lv_out_idx + 1 ] = '='.
          APPEND VALUE #( cond_field = lv_cond
                          when_true  = lv_when_true
                          tabname    = lt_tok[ lv_out_idx + 2 ] ) TO mt_outtabs.
        ENDIF.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_performed INTO lv_perf.
      IF lv_perf <> lv_display_form.
        APPEND lv_perf TO mt_data_forms.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_plain INTO lv_plain.
      IF lv_plain <> lv_display_form
         AND NOT line_exists( mt_data_forms[ table_line = lv_plain ] )
         AND NOT line_exists( lt_performed[ table_line = lv_plain ] ).
        mv_loader = lv_plain.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD read_lines.
    DATA lt_seen TYPE HASHED TABLE OF program WITH UNIQUE KEY table_line.
    DATA lt_work TYPE STANDARD TABLE OF program WITH EMPTY KEY.
    DATA lt_src  TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA lv_prog TYPE program.
    DATA lv_src  TYPE string.
    DATA lv_chk  TYPE string.
    DATA lv_kw   TYPE string.
    DATA lv_inc  TYPE string.
    DATA lv_more TYPE string.

    APPEND iv_report TO lt_work.
    WHILE lt_work IS NOT INITIAL.
      lv_prog = lt_work[ 1 ].
      DELETE lt_work INDEX 1.
      IF line_exists( lt_seen[ table_line = lv_prog ] ).
        CONTINUE.
      ENDIF.
      INSERT lv_prog INTO TABLE lt_seen.

      CLEAR lt_src.
      READ REPORT lv_prog INTO lt_src.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      LOOP AT lt_src INTO lv_src.
        lv_chk = to_upper( condense( lv_src ) ).
        IF lv_chk CP 'INCLUDE *'
           AND lv_chk NP 'INCLUDE TYPE*'
           AND lv_chk NP 'INCLUDE STRUCTURE*'
           AND lv_chk NP 'INCLUDE METHODS*'.
          SPLIT lv_chk AT space INTO lv_kw lv_inc lv_more.
          REPLACE ALL OCCURRENCES OF '.' IN lv_inc WITH ''.
          IF lv_inc IS NOT INITIAL.
            APPEND CONV program( lv_inc ) TO lt_work.
          ENDIF.
        ELSE.
          APPEND lv_src TO rt_lines.
        ENDIF.
      ENDLOOP.
    ENDWHILE.
  ENDMETHOD.


  METHOD tokens_of.
    DATA(lv) = iv_stmt.
    REPLACE ALL OCCURRENCES OF '.' IN lv WITH ''.
    REPLACE ALL OCCURRENCES OF ',' IN lv WITH ' '.
    REPLACE ALL OCCURRENCES OF ':' IN lv WITH ' '.
    SPLIT lv AT space INTO TABLE rt_tok.
    DELETE rt_tok WHERE table_line IS INITIAL.
  ENDMETHOD.


  METHOD resolve_meta.
    DATA lv_ref TYPE string.
    lv_ref = to_upper( iv_ref ).
    REPLACE ALL OCCURRENCES OF '.' IN lv_ref WITH ''.

    IF lv_ref CS '-'.
      SPLIT lv_ref AT '-' INTO DATA(lv_tab) DATA(lv_field).
      SELECT SINGLE b~rollname, c~convexit
        FROM dd03l AS a
        INNER JOIN dd04l AS b
          ON b~rollname = a~rollname
         AND b~as4local = 'A'
        INNER JOIN dd01l AS c
          ON c~domname = b~domname
         AND c~as4local = 'A'
        WHERE a~tabname   = @lv_tab
          AND a~fieldname = @lv_field
          AND a~as4local  = 'A'
        INTO @rs_meta.
      RETURN.
    ENDIF.

    READ TABLE it_symbol INTO DATA(ls_sym) WITH TABLE KEY name = lv_ref.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    IF ls_sym-tabname IS NOT INITIAL.
      rs_meta = resolve_meta( iv_ref = |{ ls_sym-tabname }-{ ls_sym-fieldname }| it_symbol = it_symbol ).
      RETURN.
    ENDIF.
    rs_meta-rollname = ls_sym-rollname.
    IF rs_meta-rollname IS NOT INITIAL.
      SELECT SINGLE c~convexit
        FROM dd04l AS b
        INNER JOIN dd01l AS c
          ON c~domname = b~domname
         AND c~as4local = 'A'
        WHERE b~rollname  = @rs_meta-rollname
          AND b~as4local  = 'A'
        INTO @rs_meta-convexit.
    ENDIF.
  ENDMETHOD.


  METHOD to_internal.
    rv_value = condense( iv_value ).
    IF rv_value IS INITIAL OR iv_rollname IS INITIAL.
      RETURN.
    ENDIF.

    DATA lr_value TYPE REF TO data.
    TRY.
        CREATE DATA lr_value TYPE (iv_rollname).
      CATCH cx_sy_create_data_error.
        RETURN.
    ENDTRY.
    ASSIGN lr_value->* TO FIELD-SYMBOL(<value>).

    IF iv_convexit IS NOT INITIAL.
      DATA(lv_fm) = CONV funcname( |CONVERSION_EXIT_{ condense( iv_convexit ) }_INPUT| ).
      CALL FUNCTION lv_fm
        EXPORTING
          input         = rv_value
        IMPORTING
          output        = <value>
        EXCEPTIONS
          error_message = 1
          OTHERS        = 2.
      IF sy-subrc <> 0.
        TRY.
            <value> = rv_value.
          CATCH cx_sy_conversion_error.
            RETURN.
        ENDTRY.
      ENDIF.
    ELSE.
      TRY.
          <value> = rv_value.
        CATCH cx_sy_conversion_error.
          RETURN.
      ENDTRY.
    ENDIF.

    rv_value = <value>.
  ENDMETHOD.


  METHOD load_variant.
    CLEAR: et_params, ev_message.

    SELECT SINGLE @abap_true
      FROM varid
      WHERE report  = @iv_report
        AND variant = @iv_variant
      INTO @DATA(lv_found).
    IF sy-subrc <> 0.
      ev_message = |变式 { iv_variant } 在报表 { iv_report } 中不存在。|.
      RETURN.
    ENDIF.

    CALL FUNCTION 'RS_VARIANT_CONTENTS'
      EXPORTING
        report               = iv_report
        variant              = iv_variant
        move_or_write        = 'M'
      TABLES
        valutab              = et_params
      EXCEPTIONS
        variant_non_existent = 1
        variant_obsolete     = 2
        error_message        = 3
        OTHERS               = 4.
    IF sy-subrc <> 0.
      ev_message = |读取变式 { iv_variant } 失败。|.
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD execute_report.
    DATA lv_prog TYPE program.
    DATA lr_data TYPE REF TO data.
    DATA lx_run  TYPE REF TO cx_root.
    FIELD-SYMBOLS <tab>  TYPE ANY TABLE.
    FIELD-SYMBOLS <copy> TYPE ANY TABLE.

    lv_prog = mv_report.
    cl_salv_bs_runtime_info=>set( EXPORTING display  = abap_false
                                            metadata = abap_true
                                            data     = abap_true ).
    TRY.
        IF it_params IS INITIAL.
          SUBMIT (lv_prog) AND RETURN.
        ELSE.
          SUBMIT (lv_prog) WITH SELECTION-TABLE it_params AND RETURN.
        ENDIF.

        cl_salv_bs_runtime_info=>get_data_ref( IMPORTING r_data = lr_data ).
        IF lr_data IS BOUND.
          ASSIGN lr_data->* TO <tab>.
          CREATE DATA rs_result-data LIKE <tab>.
          ASSIGN rs_result-data->* TO <copy>.
          <copy> = <tab>.
          rs_result-lines = lines( <tab> ).
        ENDIF.
      CATCH cx_root INTO lx_run.
        rs_result-message = |运行报表 { lv_prog } 失败: { lx_run->get_text( ) }|.
        RETURN.
      CLEANUP.
        cl_salv_bs_runtime_info=>clear_all( ).
    ENDTRY.

    IF rs_result-data IS NOT BOUND.
      rs_result-message = |报表 { lv_prog } 已执行，没有取到 ALV 数据。|.
      RETURN.
    ENDIF.

    rs_result-success = abap_true.
    rs_result-message = |报表 { lv_prog } 已执行，{ rs_result-lines } 行。|.
  ENDMETHOD.


  METHOD apply_selection.
    FIELD-SYMBOLS <field> TYPE any.
    FIELD-SYMBOLS <range> TYPE ANY TABLE.
    FIELD-SYMBOLS <line>  TYPE any.
    FIELD-SYMBOLS <comp>  TYPE any.
    DATA lt_seen  TYPE HASHED TABLE OF rsparams-selname WITH UNIQUE KEY table_line.
    DATA ls_param TYPE rsparams.
    DATA ls_def   TYPE ty_seldef.
    DATA lx_move  TYPE REF TO cx_sy_conversion_error.
    DATA lo_type  TYPE REF TO cl_abap_typedescr.
    DATA lo_line  TYPE REF TO cl_abap_datadescr.
    DATA lr_line  TYPE REF TO data.
    DATA lv_target TYPE string.

    LOOP AT mt_seldef INTO ls_def.
      IF ls_def-kind = 'S'.
        lv_target = |({ mv_report }){ ls_def-name }[]|.
        ASSIGN (lv_target) TO <range>.
        IF sy-subrc = 0.
          CLEAR <range>.
        ENDIF.
      ELSE.
        lv_target = |({ mv_report }){ ls_def-name }|.
        ASSIGN (lv_target) TO <field>.
        IF sy-subrc = 0.
          CLEAR <field>.
        ENDIF.
      ENDIF.
    ENDLOOP.

    LOOP AT it_params INTO ls_param.
      IF ls_param-kind = 'P'.
        lv_target = |({ mv_report }){ ls_param-selname }|.
        ASSIGN (lv_target) TO <field>.
        IF sy-subrc <> 0.
          rv_message = |找不到参数 { ls_param-selname }。|.
          RETURN.
        ENDIF.
        TRY.
            <field> = ls_param-low.
          CATCH cx_sy_conversion_error INTO lx_move.
            rv_message = |参数 { ls_param-selname } 赋值失败: { lx_move->get_text( ) }|.
            RETURN.
        ENDTRY.
      ELSE.
        lv_target = |({ mv_report }){ ls_param-selname }[]|.
        ASSIGN (lv_target) TO <range>.
        IF sy-subrc <> 0.
          rv_message = |找不到选择条件 { ls_param-selname }。|.
          RETURN.
        ENDIF.
        IF ls_param-low IS INITIAL AND ls_param-high IS INITIAL.
          CONTINUE.
        ENDIF.
        IF NOT line_exists( lt_seen[ table_line = ls_param-selname ] ).
          CLEAR <range>.
          INSERT ls_param-selname INTO TABLE lt_seen.
        ENDIF.

        lo_type = cl_abap_typedescr=>describe_by_data( <range> ).
        lo_line = CAST cl_abap_tabledescr( lo_type )->get_table_line_type( ).
        CREATE DATA lr_line TYPE HANDLE lo_line.
        ASSIGN lr_line->* TO <line>.
        ASSIGN COMPONENT 'SIGN' OF STRUCTURE <line> TO <comp>.
        <comp> = ls_param-sign.
        ASSIGN COMPONENT 'OPTION' OF STRUCTURE <line> TO <comp>.
        <comp> = ls_param-option.
        ASSIGN COMPONENT 'LOW' OF STRUCTURE <line> TO <comp>.
        TRY.
            <comp> = ls_param-low.
          CATCH cx_sy_conversion_error INTO lx_move.
            rv_message = |选择条件 { ls_param-selname } 的 LOW 赋值失败: { lx_move->get_text( ) }|.
            RETURN.
        ENDTRY.
        IF ls_param-high IS NOT INITIAL.
          ASSIGN COMPONENT 'HIGH' OF STRUCTURE <line> TO <comp>.
          TRY.
              <comp> = ls_param-high.
            CATCH cx_sy_conversion_error INTO lx_move.
              rv_message = |选择条件 { ls_param-selname } 的 HIGH 赋值失败: { lx_move->get_text( ) }|.
              RETURN.
          ENDTRY.
        ENDIF.
        INSERT <line> INTO TABLE <range>.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
