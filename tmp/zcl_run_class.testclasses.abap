CLASS ltcl_prepare DEFINITION FINAL
  FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_run_class.
    METHODS setup.
    METHODS params_kind_and_alpha FOR TESTING.
    METHODS variant_name_is_upper FOR TESTING.
    METHODS low_of
      IMPORTING it_params       TYPE rsparams_tt
                iv_name         TYPE rsparams-selname
      RETURNING VALUE(rv_low)   TYPE string.
ENDCLASS.


CLASS ltcl_prepare IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.


  METHOD params_kind_and_alpha.
    DATA lv_report  TYPE program.
    DATA lv_variant TYPE variant.
    DATA lt_params  TYPE rsparams_tt.
    DATA lv_message TYPE string.

    DATA(lv_ok) = mo_cut->build_request(
      EXPORTING iv_payload = `{"report":"ZCOR013","params":[` &&
                               `{"selname":"s_bukrs","low":"1100"},` &&
                               `{"selname":"s_monat","low":"202510"},` &&
                               `{"selname":"s_lead","low":"30007202"}]}`
      IMPORTING ev_report  = lv_report
                ev_variant = lv_variant
                et_params  = lt_params
                ev_message = lv_message ).

    cl_abap_unit_assert=>assert_true( act = lv_ok msg = lv_message ).
    cl_abap_unit_assert=>assert_equals( act = lv_report exp = 'ZCOR013' ).

    READ TABLE lt_params INTO DATA(ls_bukrs) WITH KEY selname = 'S_BUKRS'.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_bukrs-kind exp = 'S' ).
    cl_abap_unit_assert=>assert_equals( act = low_of( it_params = lt_params iv_name = 'S_BUKRS' ) exp = `1100` ).

    READ TABLE lt_params INTO DATA(ls_monat) WITH KEY selname = 'S_MONAT'.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_monat-kind exp = 'S' ).
    cl_abap_unit_assert=>assert_equals( act = low_of( it_params = lt_params iv_name = 'S_MONAT' ) exp = `202510` ).

    READ TABLE lt_params INTO DATA(ls_lead) WITH KEY selname = 'S_LEAD'.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_lead-kind exp = 'S' ).
    cl_abap_unit_assert=>assert_equals( act = ls_lead-sign exp = 'I' ).
    cl_abap_unit_assert=>assert_equals( act = ls_lead-option exp = 'EQ' ).
    cl_abap_unit_assert=>assert_equals( act = low_of( it_params = lt_params iv_name = 'S_LEAD' ) exp = `000030007202` ).

    cl_abap_unit_assert=>assert_equals( act = low_of( it_params = lt_params iv_name = 'P_DET' ) exp = `X` ).
  ENDMETHOD.


  METHOD variant_name_is_upper.
    DATA lv_report  TYPE program.
    DATA lv_variant TYPE variant.
    DATA lt_input   TYPE zcl_run_class=>tt_param_input.
    DATA lv_message TYPE string.

    DATA(lv_ok) = mo_cut->parse_payload(
      EXPORTING iv_payload = `{"report":"zcor013","variant":"test01"}`
      IMPORTING ev_report  = lv_report
                ev_variant = lv_variant
                et_input   = lt_input
                ev_message = lv_message ).

    cl_abap_unit_assert=>assert_true( act = lv_ok msg = lv_message ).
    cl_abap_unit_assert=>assert_equals( act = lv_report exp = 'ZCOR013' ).
    cl_abap_unit_assert=>assert_equals( act = lv_variant exp = 'TEST01' ).
  ENDMETHOD.


  METHOD low_of.
    READ TABLE it_params INTO DATA(ls_param) WITH KEY selname = iv_name.
    cl_abap_unit_assert=>assert_subrc( msg = |缺少 { iv_name }| ).
    rv_low = condense( CONV string( ls_param-low ) ).
  ENDMETHOD.

ENDCLASS.


CLASS ltcl_execute DEFINITION FINAL
  FOR TESTING
  DURATION LONG
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS variant_test01 FOR TESTING.
    METHODS params_bukrs_monat_lead FOR TESTING.
    METHODS assert_rows
      IMPORTING iv_payload TYPE string.
ENDCLASS.


CLASS ltcl_execute IMPLEMENTATION.

  METHOD variant_test01.
    assert_rows( `{"report":"ZCOR013","variant":"test01"}` ).
  ENDMETHOD.


  METHOD params_bukrs_monat_lead.
    assert_rows( `{"report":"ZCOR013","params":[` &&
                 `{"selname":"s_bukrs","low":"1100"},` &&
                 `{"selname":"s_monat","low":"202510"},` &&
                 `{"selname":"s_lead","low":"30007202"}]}` ).
  ENDMETHOD.


  METHOD assert_rows.
    DATA(ls_result) = NEW zcl_run_class( )->run_payload( iv_payload ).
    cl_abap_unit_assert=>assert_true( act = ls_result-success msg = ls_result-message ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( ls_result-lines > 0 )
      msg = |返回 { ls_result-lines } 行。{ ls_result-message }| ).
  ENDMETHOD.

ENDCLASS.
