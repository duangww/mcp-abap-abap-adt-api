CLASS zcl_run_function DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_named,
             name TYPE string,
             json TYPE string,
           END OF ty_named,
           tt_named TYPE STANDARD TABLE OF ty_named WITH EMPTY KEY.

    TYPES: BEGIN OF ty_request,
             function  TYPE string,
             variant   TYPE string,
             importing TYPE tt_named,
             changing  TYPE tt_named,
             tables    TYPE tt_named,
           END OF ty_request.

    TYPES: BEGIN OF ty_iface,
             parameter TYPE fupararef-parameter,
             paramtype TYPE fupararef-paramtype,
             structure TYPE fupararef-structure,
           END OF ty_iface,
           tt_iface TYPE HASHED TABLE OF ty_iface WITH UNIQUE KEY parameter.

    TYPES: BEGIN OF ty_json_item,
             name TYPE string,
             json TYPE string,
           END OF ty_json_item,
           tt_json_item TYPE STANDARD TABLE OF ty_json_item WITH EMPTY KEY.

    TYPES: BEGIN OF ty_exc,
             name  TYPE string,
             value TYPE i,
           END OF ty_exc,
           tt_exc TYPE STANDARD TABLE OF ty_exc WITH EMPTY KEY.

    TYPES tt_hold TYPE STANDARD TABLE OF REF TO data WITH EMPTY KEY.

    METHODS run_payload
      IMPORTING iv_payload     TYPE string
      RETURNING VALUE(rv_json) TYPE string.

    METHODS load_variant
      IMPORTING iv_func          TYPE rs38l_fnam
                iv_variant       TYPE string
                it_iface         TYPE tt_iface
      CHANGING  ct_parm          TYPE abap_func_parmbind_tab
                ct_hold          TYPE tt_hold
      RETURNING VALUE(rv_message) TYPE string.

    METHODS bind_group
      IMPORTING iv_func          TYPE rs38l_fnam
                iv_paramtype     TYPE fupararef-paramtype
                iv_kind          TYPE i
                iv_label         TYPE string
                it_named         TYPE tt_named
                it_iface         TYPE tt_iface
                iv_replace       TYPE abap_bool DEFAULT abap_true
      CHANGING  ct_parm          TYPE abap_func_parmbind_tab
                ct_hold          TYPE tt_hold
      RETURNING VALUE(rv_message) TYPE string.

    METHODS create_parameter
      IMPORTING is_iface          TYPE ty_iface
      EXPORTING er_data           TYPE REF TO data
      RETURNING VALUE(rv_message) TYPE string.

    METHODS json_object
      IMPORTING it_items      TYPE tt_json_item
      RETURNING VALUE(rv_json) TYPE string.

ENDCLASS.



CLASS zcl_run_function IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    DATA(lv_payload) = NEW zcl_run_report( )->request_payload( ).
    IF lv_payload IS INITIAL.
      out->write( '{"success":false,"function":"","variant":"","message":"输入为空。runFunction 需要 functionName；可选 variant（SE37 测试数据目录名或编号）以及 importing/changing/tables。","exception":"","exporting":{},"changing":{},"tables":{}}' ).
      RETURN.
    ENDIF.
    out->write( run_payload( lv_payload ) ).
  ENDMETHOD.


  METHOD run_payload.
    DATA ls_req   TYPE ty_request.
    DATA lt_iface TYPE tt_iface.
    DATA lt_exc   TYPE tt_exc.
    DATA lt_parm  TYPE abap_func_parmbind_tab.
    DATA lt_bind  TYPE abap_func_excpbind_tab.
    DATA lt_hold  TYPE tt_hold.
    DATA lt_out   TYPE tt_json_item.
    DATA lt_chg   TYPE tt_json_item.
    DATA lt_tab   TYPE tt_json_item.
    DATA lv_func  TYPE rs38l_fnam.
    DATA lv_var   TYPE string.
    DATA lv_msg   TYPE string.
    DATA lv_exc   TYPE string.
    DATA lv_ok    TYPE abap_bool.
    DATA lv_subrc TYPE i.
    DATA lr_out   TYPE REF TO data.
    FIELD-SYMBOLS <value> TYPE any.

    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json = iv_payload
                                   CHANGING  data = ls_req ).
      CATCH cx_root INTO DATA(lx_json).
        lv_msg = |JSON 解析失败: { lx_json->get_text( ) }|.
    ENDTRY.

    lv_func = to_upper( condense( ls_req-function ) ).
    lv_var  = condense( ls_req-variant ).
    IF lv_msg IS INITIAL AND lv_func IS INITIAL.
      lv_msg = 'JSON 中没有函数名 function。'.
    ENDIF.

    IF lv_msg IS INITIAL.
      SELECT SINGLE @abap_true FROM tfdir WHERE funcname = @lv_func INTO @DATA(lv_found).
      IF sy-subrc <> 0.
        lv_msg = |函数 { lv_func } 不存在。|.
      ENDIF.
    ENDIF.

    IF lv_msg IS INITIAL.
      SELECT parameter, paramtype, structure
        FROM fupararef
        WHERE funcname = @lv_func
        INTO TABLE @DATA(lt_raw).
      LOOP AT lt_raw INTO DATA(ls_raw).
        IF ls_raw-paramtype = 'X'.
          APPEND VALUE #( name = ls_raw-parameter value = lines( lt_exc ) + 1 ) TO lt_exc.
        ELSE.
          INSERT CORRESPONDING #( ls_raw ) INTO TABLE lt_iface.
        ENDIF.
      ENDLOOP.
      READ TABLE lt_exc TRANSPORTING NO FIELDS WITH KEY name = 'ERROR_MESSAGE'.
      IF sy-subrc <> 0.
        APPEND VALUE #( name = 'ERROR_MESSAGE' value = 90 ) TO lt_exc.
      ENDIF.
    ENDIF.

    IF lv_msg IS INITIAL AND lv_var IS NOT INITIAL.
      lv_msg = load_variant( EXPORTING iv_func = lv_func iv_variant = lv_var it_iface = lt_iface
                             CHANGING  ct_parm = lt_parm ct_hold = lt_hold ).
    ENDIF.

    IF lv_msg IS INITIAL.
      lv_msg = bind_group( EXPORTING iv_func = lv_func iv_paramtype = 'I' iv_kind = abap_func_exporting
                                     iv_label = '输入' it_named = ls_req-importing it_iface = lt_iface
                           CHANGING ct_parm = lt_parm ct_hold = lt_hold ).
    ENDIF.
    IF lv_msg IS INITIAL.
      lv_msg = bind_group( EXPORTING iv_func = lv_func iv_paramtype = 'C' iv_kind = abap_func_changing
                                     iv_label = '更改' it_named = ls_req-changing it_iface = lt_iface
                           CHANGING ct_parm = lt_parm ct_hold = lt_hold ).
    ENDIF.
    IF lv_msg IS INITIAL.
      lv_msg = bind_group( EXPORTING iv_func = lv_func iv_paramtype = 'T' iv_kind = abap_func_tables
                                     iv_label = '表' it_named = ls_req-tables it_iface = lt_iface
                           CHANGING ct_parm = lt_parm ct_hold = lt_hold ).
    ENDIF.

    IF lv_msg IS INITIAL.
      LOOP AT lt_iface INTO DATA(ls_out) WHERE paramtype = 'E' OR paramtype = 'C' OR paramtype = 'T'.
        READ TABLE lt_parm TRANSPORTING NO FIELDS WITH KEY name = ls_out-parameter.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.
        CLEAR lr_out.
        lv_msg = create_parameter( EXPORTING is_iface = ls_out IMPORTING er_data = lr_out ).
        IF lv_msg IS NOT INITIAL.
          EXIT.
        ENDIF.
        APPEND lr_out TO lt_hold.
        INSERT VALUE abap_func_parmbind(
                 name  = ls_out-parameter
                 kind  = COND #( WHEN ls_out-paramtype = 'E' THEN abap_func_importing
                                 WHEN ls_out-paramtype = 'C' THEN abap_func_changing
                                 ELSE abap_func_tables )
                 value = lr_out ) INTO TABLE lt_parm.
      ENDLOOP.
    ENDIF.

    IF lv_msg IS INITIAL.
      LOOP AT lt_exc INTO DATA(ls_exc).
        INSERT VALUE abap_func_excpbind( name = ls_exc-name value = ls_exc-value ) INTO TABLE lt_bind.
      ENDLOOP.
      TRY.
          CALL FUNCTION lv_func
            PARAMETER-TABLE lt_parm
            EXCEPTION-TABLE lt_bind.
          lv_subrc = sy-subrc.
          IF lv_subrc <> 0.
            lv_ok = abap_false.
            READ TABLE lt_exc INTO ls_exc WITH KEY value = lv_subrc.
            lv_exc = COND #( WHEN sy-subrc = 0 THEN ls_exc-name ELSE |{ lv_subrc }| ).
            IF lv_exc = 'ERROR_MESSAGE'.
              lv_msg = |{ sy-msgid } { sy-msgno } { sy-msgv1 } { sy-msgv2 } { sy-msgv3 } { sy-msgv4 }|.
            ELSE.
              lv_msg = |函数 { lv_func } 抛出异常 { lv_exc }。|.
            ENDIF.
          ELSE.
            lv_ok = abap_true.
            lv_msg = COND #( WHEN lv_var IS INITIAL
                             THEN |函数 { lv_func } 已执行。|
                             ELSE |函数 { lv_func } 已用测试数据 { lv_var } 执行。| ).
          ENDIF.
        CATCH cx_root INTO DATA(lx_call).
          lv_msg = |调用函数 { lv_func } 失败: { lx_call->get_text( ) }|.
      ENDTRY.
    ENDIF.

    LOOP AT lt_parm INTO DATA(ls_parm).
      ASSIGN ls_parm-value->* TO <value>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      DATA(lv_piece) = /ui2/cl_json=>serialize(
                         data        = <value>
                         compress    = abap_true
                         pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
      CASE ls_parm-kind.
        WHEN abap_func_importing.
          APPEND VALUE #( name = ls_parm-name json = lv_piece ) TO lt_out.
        WHEN abap_func_changing.
          APPEND VALUE #( name = ls_parm-name json = lv_piece ) TO lt_chg.
        WHEN abap_func_tables.
          APPEND VALUE #( name = ls_parm-name json = lv_piece ) TO lt_tab.
      ENDCASE.
    ENDLOOP.

    rv_json = |\{"success":{ COND string( WHEN lv_ok = abap_true THEN 'true' ELSE 'false' ) }| &&
              |,"function":{ /ui2/cl_json=>serialize( data = CONV string( lv_func ) compress = abap_true ) }| &&
              |,"variant":{ /ui2/cl_json=>serialize( data = lv_var compress = abap_true ) }| &&
              |,"message":{ /ui2/cl_json=>serialize( data = lv_msg compress = abap_true ) }| &&
              |,"exception":{ /ui2/cl_json=>serialize( data = lv_exc compress = abap_true ) }| &&
              |,"exporting":{ json_object( lt_out ) }| &&
              |,"changing":{ json_object( lt_chg ) }| &&
              |,"tables":{ json_object( lt_tab ) }\}|.
  ENDMETHOD.


  METHOD load_variant.
    DATA lt_dir     TYPE STANDARD TABLE OF eudatadir WITH EMPTY KEY.
    DATA ls_dir     TYPE eudatadir.
    DATA lt_cont    TYPE STANDARD TABLE OF swcont WITH EMPTY KEY.
    DATA lv_nummer  TYPE eudatadir-nummer.
    DATA lv_needle  TYPE string.
    DATA lv_title   TYPE string.
    DATA lv_kind    TYPE i.
    DATA lr_data    TYPE REF TO data.
    FIELD-SYMBOLS <value> TYPE any.

    lv_needle = condense( iv_variant ).
    IF lv_needle IS INITIAL.
      RETURN.
    ENDIF.

    CALL FUNCTION 'RS_TESTDATA_DIRECTORY_GET'
      EXPORTING
        functionname        = iv_func
      TABLES
        te_datadir          = lt_dir
      EXCEPTIONS
        function_not_found  = 1
        no_data             = 2
        OTHERS              = 3.
    IF sy-subrc <> 0.
      rv_message = |函数 { iv_func } 没有 SE37 测试数据目录。|.
      RETURN.
    ENDIF.

    LOOP AT lt_dir INTO ls_dir.
      lv_title = condense( ls_dir-titel ).
      IF to_upper( lv_title ) = to_upper( lv_needle )
         OR condense( ls_dir-nummer ) = lv_needle.
        lv_nummer = ls_dir-nummer.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_nummer IS INITIAL.
      rv_message = |函数 { iv_func } 的测试数据目录中找不到变式 { iv_variant }。|.
      RETURN.
    ENDIF.

    CALL FUNCTION 'SFCS_FA_PARAMETERS_GET_TABLE'
      EXPORTING
        funcname                       = iv_func
        id                             = lv_nummer
        location                       = 'F'
        mode                           = 'I'
        suppress_file_existence_check  = space
      TABLES
        container                      = lt_cont
      EXCEPTIONS
        missing_functionname           = 1
        missing_filename               = 2
        file_not_found                 = 3
        OTHERS                         = 4.
    IF sy-subrc <> 0.
      rv_message = |无法装载函数 { iv_func } 的测试数据 { iv_variant }。|.
      RETURN.
    ENDIF.

    LOOP AT it_iface INTO DATA(ls_iface) WHERE paramtype = 'I'
                                            OR paramtype = 'C'
                                            OR paramtype = 'T'.
      CLEAR lr_data.
      rv_message = create_parameter( EXPORTING is_iface = ls_iface IMPORTING er_data = lr_data ).
      IF rv_message IS NOT INITIAL.
        RETURN.
      ENDIF.
      ASSIGN lr_data->* TO <value>.
      IF sy-subrc <> 0.
        rv_message = |参数 { ls_iface-parameter } 无法赋值。|.
        RETURN.
      ENDIF.

      TRY.
          IF ls_iface-paramtype = 'T'.
            CALL FUNCTION 'SFCS_FA_TABLES_GET'
              EXPORTING
                function  = iv_func
                parameter = ls_iface-parameter
              IMPORTING
                value     = <value>
              EXCEPTIONS
                generation_error = 1
                OTHERS           = 2.
          ELSE.
            CALL FUNCTION 'SFCS_FA_PARAMETER_GET'
              EXPORTING
                function  = iv_func
                parameter = ls_iface-parameter
                direction = 'I'
              IMPORTING
                value     = <value>
              EXCEPTIONS
                generation_error = 1
                OTHERS           = 2.
          ENDIF.
        CATCH cx_root INTO DATA(lx_get).
          rv_message = |读取测试参数 { ls_iface-parameter } 失败: { lx_get->get_text( ) }|.
          RETURN.
      ENDTRY.
      IF sy-subrc <> 0.
        rv_message = |读取测试参数 { ls_iface-parameter } 失败。|.
        RETURN.
      ENDIF.

      lv_kind = COND #( WHEN ls_iface-paramtype = 'I' THEN abap_func_exporting
                        WHEN ls_iface-paramtype = 'C' THEN abap_func_changing
                        ELSE abap_func_tables ).
      APPEND lr_data TO ct_hold.
      INSERT VALUE abap_func_parmbind(
               name  = ls_iface-parameter
               kind  = lv_kind
               value = lr_data ) INTO TABLE ct_parm.
    ENDLOOP.
  ENDMETHOD.


  METHOD bind_group.
    DATA lr_data TYPE REF TO data.
    FIELD-SYMBOLS <value> TYPE any.

    LOOP AT it_named INTO DATA(ls_named).
      DATA(lv_name) = to_upper( condense( ls_named-name ) ).
      IF lv_name IS INITIAL.
        CONTINUE.
      ENDIF.
      READ TABLE it_iface INTO DATA(ls_iface) WITH TABLE KEY parameter = lv_name.
      IF sy-subrc <> 0 OR ls_iface-paramtype <> iv_paramtype.
        rv_message = |函数 { iv_func } 没有{ iv_label }参数 { lv_name }。|.
        RETURN.
      ENDIF.

      READ TABLE ct_parm ASSIGNING FIELD-SYMBOL(<parm>) WITH KEY name = lv_name.
      IF sy-subrc = 0 AND iv_replace = abap_true.
        ASSIGN <parm>-value->* TO <value>.
      ELSE.
        CLEAR lr_data.
        rv_message = create_parameter( EXPORTING is_iface = ls_iface IMPORTING er_data = lr_data ).
        IF rv_message IS NOT INITIAL.
          RETURN.
        ENDIF.
        ASSIGN lr_data->* TO <value>.
        APPEND lr_data TO ct_hold.
        INSERT VALUE abap_func_parmbind( name = lv_name kind = iv_kind value = lr_data ) INTO TABLE ct_parm.
      ENDIF.

      TRY.
          /ui2/cl_json=>deserialize( EXPORTING json = ls_named-json
                                     CHANGING  data = <value> ).
        CATCH cx_root INTO DATA(lx_move).
          rv_message = |参数 { lv_name } 无法赋值: { lx_move->get_text( ) }|.
          RETURN.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD create_parameter.
    DATA lo_type  TYPE REF TO cl_abap_datadescr.
    DATA lv_tab   TYPE string.
    DATA lv_field TYPE string.

    IF is_iface-structure IS INITIAL.
      rv_message = |参数 { is_iface-parameter } 没有类型。|.
      RETURN.
    ENDIF.

    TRY.
        IF is_iface-structure CS '-'.
          SPLIT is_iface-structure AT '-' INTO lv_tab lv_field.
          DATA(lo_struct) = CAST cl_abap_structdescr(
                              cl_abap_typedescr=>describe_by_name( lv_tab ) ).
          lo_type = lo_struct->get_component_type( CONV abap_compname( lv_field ) ).
          IF lo_type IS NOT BOUND.
            rv_message = |类型 { is_iface-structure } 不存在。|.
            RETURN.
          ENDIF.
          CREATE DATA er_data TYPE HANDLE lo_type.
        ELSE.
          DATA(lo_desc) = cl_abap_typedescr=>describe_by_name( is_iface-structure ).
          IF is_iface-paramtype = 'T' AND lo_desc->kind <> cl_abap_typedescr=>kind_table.
            CREATE DATA er_data TYPE TABLE OF (is_iface-structure).
          ELSE.
            lo_type = CAST cl_abap_datadescr( lo_desc ).
            CREATE DATA er_data TYPE HANDLE lo_type.
          ENDIF.
        ENDIF.
      CATCH cx_root INTO DATA(lx_type).
        rv_message = |参数 { is_iface-parameter } 的类型 { is_iface-structure } 无法创建: { lx_type->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD json_object.
    DATA lv_sep TYPE abap_bool.
    rv_json = `{`.
    LOOP AT it_items INTO DATA(ls_item).
      IF lv_sep = abap_true.
        rv_json = rv_json && `,`.
      ENDIF.
      lv_sep = abap_true.
      rv_json = rv_json && |"{ to_lower( ls_item-name ) }":{ ls_item-json }|.
    ENDLOOP.
    rv_json = rv_json && `}`.
  ENDMETHOD.

ENDCLASS.
