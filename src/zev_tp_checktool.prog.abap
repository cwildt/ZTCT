REPORT  zev_tp_checktool.
*&******************************************************************&*
*& Report   : ZEV_TP_CHECKTOOL                                      &*
*& Version  : 1.00                                                  &*
*&------------------------------------------------------------------&*
*&                                                                  &*
*& Copyright (c) 2012, E.Vleeshouwers                               &*
*& All rights reserved.                                             &*
*&                                                                  &*
*& Redistribution and use in source and binary forms, with or       &*
*& without modification, are permitted provided that the following  &*
*& conditions are met:                                              &*
*&                                                                  &*
*& 1. Redistributions of source code must retain the above          &*
*&    copyright notice, this list of conditions and the following   &*
*&    disclaimer.                                                   &*
*&                                                                  &*
*& 2. Redistributions in binary form must reproduce the above       &*
*&    copyright notice, this list of conditions and the following   &*
*&    disclaimer in the documentation and/or other materials        &*
*&    provided with the distribution.                               &*
*&                                                                  &*
*& 3. Neither the name of the copyright holder nor the names of its &*
*&    contributors may be used to endorse or promote products       &*
*&    derived from this software without specific prior written     &*
*&    permission.                                                   &*
*&                                                                  &*
*& THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND           &*
*& CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,      &*
*& INCLUDING, BUT NOT  LIMITED TO, THE IMPLIED WARRANTIES OF        &*
*& MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE         &*
*& DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR            &*
*& CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,     &*
*& SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,         &*
*& BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; &*
*& LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER &*
*& CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,      &*
*& STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)    &*
*& ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF      &*
*& ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.                       &*
*&                                                                  &*
*&------------------------------------------------------------------&*
*& Program Details                                                  &*
*&------------------------------------------------------------------&*
*& Title    : Transport checking tool (on object level)             &*
*& Purpose  : Check transport objects before moving to production   &*
*&------------------------------------------------------------------&*
* SOURCE: https://github.com/ZEdwin/ZTCT
* BLOG (SCN):
* http://scn.sap.com/community/abap/blog/2013/05/31/transport-
* checking-tool-object-level
*--------------------------------------------------------------------*
* INSTALLATION
*--------------------------------------------------------------------*
* Use SAPLINK to import the Nugget file (located under Releases).
* This will only install a local program (R3TR PROG: this includes
* report texts and program documentation.
*
*&------------------------------------------------------------------&*
*& Change History                                                   &*
*&------------------------------------------------------------------&*
TYPE-POOLS: ctslg. "Types for Function Group TR_LOG_OVERVIEW
TYPE-POOLS: icon.  "Assignment: Icon Names in List of ASCII Codes
TYPE-POOLS: slis.  "Global types for generic list modules
TYPE-POOLS: stms.  "Transport Management System: Global Types
TYPE-POOLS: abap.

* Class for handling Events
CLASS: lcl_eventhandler_ztct DEFINITION DEFERRED.
CLASS: lcl_ztct              DEFINITION DEFERRED.

DATA: e070       TYPE e070.       "CTS: Header
DATA: e071       TYPE e071.       "CTS: Object Entries Requests/Task
DATA: vrsd       TYPE vrsd.       "Version management: directory table
DATA: ctsproject TYPE ctsproject. "Assignm. of CTS Proj. to Ext. Proj.

*--------------------------------------------------------------------*
* Data definitions
*--------------------------------------------------------------------*
* Database tables:
TABLES: sscrfields.      "Fields on selection screens
CONSTANTS:
       co_months              TYPE numc3        VALUE '012'.

DATA:  ra_project_trkorrs     TYPE RANGE OF ctsproject-trkorr.
DATA:  st_project_trkorrs     LIKE LINE  OF ra_project_trkorrs.
DATA:  ra_systems             TYPE RANGE OF tmscsys-sysnam.
DATA:  st_systems             LIKE LINE  OF ra_systems.

* Global data declarations:
DATA:  tp_prefix              TYPE char5.
DATA:  ta_sapsystems          TYPE TABLE OF tmscsys.
DATA:  st_sapsystems          TYPE tmscsys.
DATA:  st_tcesyst             TYPE tcesyst.
DATA:  st_smp_dyntxt          TYPE smp_dyntxt.
DATA:  tp_dokl_object         TYPE doku_obj. "To check existence of doc

DATA:  ta_trkorr_range        TYPE RANGE OF e070-trkorr.
DATA:  st_trkorr_range        LIKE LINE OF ta_trkorr_range.
DATA:  ta_project_range       TYPE RANGE OF ctsproject-trkorr.
DATA:  ta_date_range          TYPE RANGE OF as4date.
DATA:  ta_excluded_objects    TYPE RANGE OF trobj_name.
DATA:  tp_transport_descr     TYPE as4text.
DATA:  tp_project_reference   TYPE trvalue.
* Process type is used to identify if a list is build (1),
* uploaded (2) or the program is used for version checking (3)
DATA:  tp_process_type        TYPE i.
* Date from for transport collection (passed to class)
DATA:  tp_date_from           TYPE as4date.
* To determine transport track on selection screen
DATA:  ta_prev_systems        TYPE tmscsyss.
DATA:  st_prev_system         TYPE tmscsys.
DATA:  ta_system_track        TYPE tcesys.
DATA:  st_system_track        TYPE sysname.
DATA:  ta_targets             TYPE trsysclis.
DATA:  st_target              TYPE trsyscli.
DATA:  tp_sysname             TYPE sysname.
DATA:  tp_index               TYPE sytabix.
DATA:  tp_msg                 TYPE string.

*--------------------------------------------------------------------*
* Data - ALV
*--------------------------------------------------------------------*
* Declaration for ALV Grid
DATA: rf_table                TYPE REF TO cl_salv_table.
DATA: rf_table_xls            TYPE REF TO cl_salv_table.
DATA: rf_conflicts            TYPE REF TO cl_salv_table.
DATA: rf_table_keys           TYPE REF TO cl_salv_table.
DATA: rf_handle_events        TYPE REF TO lcl_eventhandler_ztct.
DATA: rf_events_table         TYPE REF TO cl_salv_events_table.

* Exception handling
DATA: rf_root                 TYPE REF TO cx_root.
DATA: rf_ztct                 TYPE REF TO lcl_ztct.

*----------------------------------------------------------------------*
*       CLASS lcl_eventhandler_ztct DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_eventhandler_ztct DEFINITION FRIENDS lcl_ztct.

  PUBLIC SECTION.
    CLASS-DATA:
      rf_conflicts  TYPE REF TO cl_salv_table,
      rf_table_keys TYPE REF TO cl_salv_table.

    CLASS-METHODS on_function_click
      FOR EVENT if_salv_events_functions~added_function
        OF cl_salv_events_table IMPORTING e_salv_function.

    CLASS-METHODS: on_double_click
      FOR EVENT double_click
        OF cl_salv_events_table IMPORTING row column.

    CLASS-METHODS: on_link_click
      FOR EVENT link_click
        OF cl_salv_events_table IMPORTING row column.

    CLASS-METHODS: on_double_click_popup
      FOR EVENT double_click
        OF cl_salv_events_table IMPORTING row column.

    CLASS-METHODS: on_link_click_popup
      FOR EVENT link_click
        OF cl_salv_events_table IMPORTING row column.

ENDCLASS.                    "lcl_eventhandler_ztct DEFINITION

*----------------------------------------------------------------------*
*       CLASS lcl_ztct DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_ztct DEFINITION FRIENDS lcl_eventhandler_ztct.

  PUBLIC SECTION.

    TYPES: ra_trkorr                 TYPE RANGE OF trkorr.
    TYPES: ra_excluded_objects       TYPE RANGE OF trobj_name.
    TYPES: ra_date                   TYPE RANGE OF as4date.
    DATA:  ls_excluded_objects       LIKE LINE  OF ta_excluded_objects.
    TYPES: BEGIN OF ty_request_details,
             trkorr         TYPE trkorr,
             checked        TYPE icon_l4,
             info           TYPE icon_l4,
             tr_descr       TYPE as4text,
             dev            TYPE icon_l4,
             qas            TYPE icon_l4,
             retcode        TYPE char04,
             prd            TYPE icon_l4,
             warning_lvl    TYPE icon_d,
*            Warning_rank: The higher the number,
*            the more serious the error
             warning_rank   TYPE numc4,
             warning_txt    TYPE text74,
             pgmid          TYPE pgmid,
             object         TYPE trobjtype,
             obj_name       TYPE trobj_name,
             objkey         TYPE trobj_name,
             keyobject      TYPE trobjtype,
             keyobjname     TYPE tabname,
             tabkey         TYPE tabkey,
             checked_by     TYPE syuname,
             as4date        TYPE as4date,
             as4time        TYPE as4time,
             as4user        TYPE as4user,
             status_text    TYPE char20,
             trfunction_txt TYPE val_text,
             project        TYPE cts_id,
             project_descr  TYPE as4text,
             objfunc        TYPE objfunc,
             flag           TYPE flag,
             trstatus       TYPE trstatus,
             trfunction     TYPE trfunction,
             re_import      TYPE char20.
    TYPES:   t_color        TYPE lvc_t_scol,
           END OF  ty_request_details.

    TYPES: tt_request_details TYPE STANDARD TABLE OF ty_request_details
                              WITH DEFAULT KEY.

    TYPES: BEGIN OF lty_tables_with_keys,
             tabname  TYPE trobj_name,
             ddtext   TYPE as4text,
             counter  TYPE i, "lvc_outlen,
           END OF lty_tables_with_keys.
    DATA: table_keys      TYPE TABLE OF lty_tables_with_keys.
    DATA: table_keys_line TYPE lty_tables_with_keys.

    CONSTANTS:
      co_info                 TYPE icon_d VALUE '@0S@'. "ICON_INFORMATION

*   Attributes
    DATA:  main_list          TYPE tt_request_details.
    DATA:  main_list_line     TYPE ty_request_details.
    DATA:  main_list_xls      TYPE tt_request_details.
    DATA:  main_list_line_xls TYPE ty_request_details.
    DATA:  conflicts          TYPE tt_request_details.
    DATA:  st_request         TYPE ctslg_request_info.
    DATA:  st_steps           TYPE ctslg_step.
    DATA:  st_actions         TYPE ctslg_action.
    DATA:  tp_tabkey          TYPE trobj_name.
    DATA:  tp_lines           TYPE i.
    DATA:  tp_tab             TYPE char1
                                   VALUE cl_abap_char_utilities=>horizontal_tab.
    DATA: lp_save_restriction TYPE salv_de_layout_restriction.

*   Methods
    METHODS: constructor.
    METHODS: execute.
    METHODS: refresh_alv.
    METHODS: get_tp_prefix            IMPORTING im_dev              TYPE sysname   OPTIONAL
                                      RETURNING value(re_tp_prefix) TYPE char5.
    METHODS: get_filename             EXPORTING ex_file             TYPE localfile.
    METHODS: set_check_flag           IMPORTING im_check_flag       TYPE abap_bool OPTIONAL.
    METHODS: set_check_ddic           IMPORTING im_check_ddic       TYPE abap_bool OPTIONAL.
    METHODS: set_check_tabkeys        IMPORTING im_check_tabkeys    TYPE abap_bool OPTIONAL.
    METHODS: set_clear_checked        IMPORTING im_clear_checked    TYPE abap_bool OPTIONAL.
    METHODS: set_skip_buffer_chk      IMPORTING im_skip_buffer_chk  TYPE abap_bool OPTIONAL.
    METHODS: set_trkorr_range         IMPORTING im_trkorr_range     TYPE ra_trkorr OPTIONAL.
    METHODS: set_project_range        IMPORTING im_project_range    TYPE ra_trkorr OPTIONAL.
    METHODS: set_date_range           IMPORTING im_date_range       TYPE ra_date   OPTIONAL.
    METHODS: set_excluded_objects     IMPORTING im_excluded_objects TYPE ra_excluded_objects OPTIONAL.
    METHODS: set_search_string        IMPORTING im_search_string    TYPE as4text   OPTIONAL.
    METHODS: set_user_layout          IMPORTING im_user_layout      TYPE abap_bool OPTIONAL.
    METHODS: set_process_type         IMPORTING im_process_type     TYPE i.
    METHODS: set_skiplive             IMPORTING im_skiplive         TYPE abap_bool OPTIONAL.
    METHODS: set_filename             IMPORTING im_filename         TYPE localfile OPTIONAL.
    METHODS: set_systems              IMPORTING im_dev_system       TYPE sysname
                                                im_qas_system       TYPE sysname
                                                im_prd_system       TYPE sysname.
    METHODS: set_building_conflict_popup IMPORTING im_building_conflict_popup TYPE abap_bool OPTIONAL.
    METHODS: go_back_months           IMPORTING im_backmonths	      TYPE numc3
                                                im_currdate         TYPE sydatum
                                      RETURNING value(re_date)      TYPE sydatum.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_tms_mgr_buffer,
                request        TYPE  tmsbuffer-trkorr,
                target_system  TYPE  tmscsys-sysnam,
                request_infos  TYPE  stms_wbo_requests,
           END   OF ty_tms_mgr_buffer.
    TYPES: tt_tms_mgr_buffer   TYPE HASHED TABLE OF ty_tms_mgr_buffer
                               WITH UNIQUE KEY request target_system.

    DATA:  tms_mgr_buffer      TYPE tt_tms_mgr_buffer.
    DATA:  tms_mgr_buffer_line TYPE ty_tms_mgr_buffer.
    TYPES: BEGIN OF ty_ddic_e071,
             trkorr   TYPE trkorr,
             pgmid    TYPE pgmid,
             object   TYPE trobjtype,
             obj_name TYPE trobj_name,
           END OF ty_ddic_e071.
    TYPES: tt_ddic_e071 TYPE STANDARD TABLE OF ty_ddic_e071.
    DATA:  ta_ddic_e071 TYPE tt_ddic_e071.
    CONSTANTS:
      co_error           TYPE icon_d       VALUE '@F1@', "ICON_LED_RED
      co_tp_fail         TYPE icon_d       VALUE '@2O@', "ICON_SYSTEM_CANCEL
      co_ddic            TYPE icon_d       VALUE '@CY@', "ICON_INCOMPLETE
      co_warn            TYPE icon_d       VALUE '@5D@', "ICON_LED_YELLOW
      co_okay            TYPE icon_d       VALUE '@5B@', "ICON_LED_GREEN
      co_checked         TYPE icon_d       VALUE '@01@', "ICON_CHECKED
      co_hint            TYPE icon_d       VALUE '@AI@', "ICON_HINT
      co_alert           TYPE icon_d       VALUE '@03@', "ICON_FAILURE
      co_scrap           TYPE icon_d       VALUE '@K3@', "ICON_SCRAP
      co_docu            TYPE icon_d       VALUE '@DH@', "ICON_PROTOCOL
      co_inact           TYPE icon_d       VALUE '@BZ@'. "ICON_LED_INACTIVE
    CONSTANTS:
      co_okay_rank       TYPE i            VALUE 0,  "ICON_LED_GREEN
      co_alert0_rank     TYPE i            VALUE 5,  "ICON_FAILURE
      co_alert1_rank     TYPE i            VALUE 6,  "ICON_FAILURE
      co_alert2_rank     TYPE i            VALUE 7,  "ICON_FAILURE
      co_alert3_rank     TYPE i            VALUE 8,  "ICON_FAILURE
      co_hint1_rank      TYPE i            VALUE 10, "ICON_HINT
      co_hint2_rank      TYPE i            VALUE 12, "ICON_HINT
      co_hint3_rank      TYPE i            VALUE 14, "ICON_HINT
      co_hint4_rank      TYPE i            VALUE 16, "ICON_HINT
      co_info_rank       TYPE i            VALUE 20, "ICON_INFORMATION
      co_warn_rank       TYPE i            VALUE 50, "ICON_LED_YELLOW
      co_tp_fail_rank    TYPE i            VALUE 97, "ICON_SYSTEM_CANCEL
      co_ddic_rank       TYPE i            VALUE 98, "ICON_INCOMPLETE
      co_error_rank      TYPE i            VALUE 99. "ICON_LED_RED
    CONSTANTS:
      co_non_charlike    TYPE string       VALUE 'h'.

    DATA: lp_alert0_text TYPE text74.
    DATA: lp_alert1_text TYPE text74.
    DATA: lp_alert2_text TYPE text74.
    DATA: lp_alert3_text TYPE text74.
    DATA: lp_hint1_text  TYPE text74.
    DATA: lp_hint2_text  TYPE text74.
    DATA: lp_hint3_text  TYPE text74.
    DATA: lp_hint4_text  TYPE text74.
    DATA: lp_info_text   TYPE text74.
    DATA: lp_fail_text   TYPE text74.
    DATA: lp_warn_text   TYPE text74.
    DATA: lp_error_text  TYPE text74.
    DATA: lp_ddic_text TYPE text74.

* Attributes
    DATA:  project_trkorrs            TYPE ra_trkorr.
    DATA:  prefix                     TYPE char5.
    DATA:  aggr_tp_list_of_objects    TYPE tt_request_details.
    DATA:  add_to_main                TYPE tt_request_details.
    DATA:  tab_delimited              TYPE table_of_strings.
    DATA:  conflict_line              TYPE ty_request_details.
    DATA:  line_found_in_list         TYPE ty_request_details.
    DATA:  total(10)                  TYPE n.
    DATA:  ddic_objects               TYPE string_table.
    DATA:  ddic_objects_sub           TYPE string_table.
    DATA:  ddic_e071                  TYPE tt_ddic_e071.
    DATA:  ddic_e071_line             TYPE ty_ddic_e071.
    DATA:  where_used                 TYPE sci_findlst.
    DATA:  where_used_line            TYPE rsfindlst.
    DATA:  check_flag                 TYPE abap_bool.
    DATA:  check_ddic                 TYPE abap_bool.
    DATA:  check_tabkeys              TYPE abap_bool.
    DATA:  clear_checked              TYPE abap_bool.
    DATA:  skip_buffer_chk            TYPE abap_bool.
    DATA:  trkorr_range               TYPE ra_trkorr.
    DATA:  project_range              TYPE ra_trkorr.
    DATA:  date_range                 TYPE ra_date.
    DATA:  excluded_objects           TYPE ra_excluded_objects.
    DATA:  search_string              TYPE as4text.
    DATA:  user_layout                TYPE abap_bool.
    DATA:  process_type               TYPE i.
    DATA:  skiplive                   TYPE abap_bool.
    DATA:  filename                   TYPE string.
    DATA:  dev_system                 TYPE sysname.
    DATA:  qas_system                 TYPE sysname.
    DATA:  prd_system                 TYPE sysname.
    DATA:  tooltips                   TYPE REF TO cl_salv_tooltips.
    DATA:  building_conflict_popup    TYPE flag.

    METHODS: refresh_import_queues.
    METHODS: handle_error             IMPORTING rf_oref             TYPE REF TO cx_root.
    METHODS: flag_for_process         IMPORTING rows                TYPE salv_t_row
                                                cell                TYPE salv_s_cell.
    METHODS: get_main_transports      IMPORTING im_trkorr_range     TYPE gtabkey_trkorrt.
    METHODS: get_tp_info              IMPORTING im_trkorr           TYPE trkorr
                                                im_obj_name         TYPE trobj_name
                                      RETURNING value(re_line)      TYPE ty_request_details.
    METHODS: get_added_objects        IMPORTING im_to_add           TYPE ra_trkorr
                                      EXPORTING ex_to_add           TYPE tt_request_details.
    METHODS: add_to_list              IMPORTING im_to_add           TYPE tt_request_details
                                      EXPORTING ex_main             TYPE tt_request_details.
    METHODS: build_conflict_popup     IMPORTING rows                TYPE salv_t_row
                                                cell                TYPE salv_s_cell.
    METHODS: delete_tp_from_list      IMPORTING rows                TYPE salv_t_row
                                                cell                TYPE salv_s_cell.
    METHODS: flag_same_objects        EXPORTING ex_main_list        TYPE tt_request_details.
    METHODS: mark_all_tp_records      IMPORTING im_cell             TYPE salv_s_cell
                                      CHANGING  im_rows             TYPE salv_t_row.
    METHODS: main_to_tab_delimited    IMPORTING im_main_list        TYPE tt_request_details
                                      EXPORTING ex_tab_delimited    TYPE table_of_strings.
    METHODS: tab_delimited_to_main    IMPORTING im_tab_delimited    TYPE table_of_strings
                                      EXPORTING ex_main_list        TYPE tt_request_details.
    METHODS: display_transport        IMPORTING im_trkorr           TYPE trkorr.
    METHODS: display_user             IMPORTING im_user             TYPE syuname.
    METHODS: display_docu             IMPORTING im_trkorr           TYPE trkorr.
    METHODS: check_if_in_list         IMPORTING im_line             TYPE ty_request_details
                                                im_tabix            TYPE sytabix
                                      EXPORTING ex_line             TYPE ty_request_details.
    METHODS: check_documentation      IMPORTING im_trkorr           TYPE trkorr
                                      CHANGING  ch_table            TYPE tt_request_details.
    METHODS: docu_call                IMPORTING im_object           TYPE doku_obj.
    METHODS: clear_flags.
    METHODS: column_settings          IMPORTING im_column_ref       TYPE salv_t_column_ref
                                                im_rf_columns_table TYPE REF TO cl_salv_columns_table
                                                im_table            TYPE REF TO cl_salv_table.
    METHODS: is_empty_column          IMPORTING im_column           TYPE lvc_fname
                                                im_table            TYPE tt_request_details
                                      RETURNING value(re_is_empty)  TYPE abap_bool.
*    METHODS: refresh_alv.
    METHODS: display_excel            IMPORTING im_table            TYPE tt_request_details.
    METHODS: set_tp_prefix            IMPORTING im_dev              TYPE sysname OPTIONAL.
    METHODS: top_of_page              EXPORTING ex_form_element     TYPE REF TO cl_salv_form_element.
    METHODS: check_if_same_object     IMPORTING im_line             TYPE ty_request_details
                                                im_newer_older      TYPE ty_request_details
                                      EXPORTING ex_tabkey           TYPE trobj_name
                                                ex_return           TYPE c.
    METHODS: sort_main_list.
    METHODS: determine_warning_text   IMPORTING im_highest_rank     TYPE numc4
                                      EXPORTING ex_highest_text     TYPE text74.
    METHODS: get_tps_for_same_object  IMPORTING im_line             TYPE ty_request_details
                                      EXPORTING ex_newer            TYPE tt_request_details
                                                ex_older            TYPE tt_request_details.
    METHODS: progress_indicator       IMPORTING im_counter          TYPE sytabix
                                                im_object           TYPE trobj_name
                                                im_total            TYPE numc10
                                                im_text             TYPE itex132
                                                im_flag             TYPE c.
    METHODS: alv_xls_init             EXPORTING ex_rf_table         TYPE REF TO cl_salv_table
                                      CHANGING  ch_table            TYPE table.
    METHODS: alv_xls_output.
    METHODS: prepare_ddic_check.
    METHODS: set_ddic_objects.
    METHODS: do_ddic_check            CHANGING  ch_main_list        TYPE tt_request_details.
    METHODS: set_properties_conflicts IMPORTING im_table            TYPE tt_request_details
                                      EXPORTING ex_xend             TYPE i.
    METHODS: get_data                 IMPORTING im_trkorr_range     TYPE gtabkey_trkorrt.
    METHODS: check_for_conflicts      CHANGING  ch_main_list        TYPE tt_request_details.
    METHODS: build_table_keys_popup.
    METHODS: add_table_keys_to_list   EXPORTING table               TYPE tt_request_details.
    METHODS: get_additional_tp_info   CHANGING  ch_table            TYPE tt_request_details.
    METHODS: gui_upload               IMPORTING im_filename         TYPE string
                                      EXPORTING ex_tab_delimited    TYPE table_of_strings
                                                ex_cancelled        TYPE abap_bool.
    METHODS: determine_col_width      IMPORTING im_field            TYPE any
                                      CHANGING  ex_colwidth         TYPE lvc_outlen.
    METHODS: check_colwidth           IMPORTING im_name             TYPE abap_compname
                                                im_colwidth         TYPE lvc_outlen
                                      RETURNING value(re_colwidth)  TYPE lvc_outlen.
    METHODS: remove_tp_in_prd.
    METHODS: version_check.
    METHODS: alv_init.
    METHODS: set_color.
    METHODS: alv_set_properties       IMPORTING im_table            TYPE REF TO cl_salv_table.
    METHODS: alv_set_tooltips         IMPORTING im_table            TYPE REF TO cl_salv_table.
    METHODS: alv_output.
    METHODS: set_where_used.
    METHODS: get_import_datetime_qas  IMPORTING im_trkorr          TYPE trkorr
                                      EXPORTING ex_as4time         TYPE as4time
                                                ex_as4date         TYPE as4date
                                                ex_return          TYPE sysubrc.
ENDCLASS.                    "lcl_ztct DEFINITION

*--------------------------------------------------------------------*
* Selection screen Build
*--------------------------------------------------------------------*

* Possibility to add a button on the selection screen application
* toolbar (If required, uncomment). Function text and icon is filled
* in AT SELECTION-SCREEN OUTPUT
* SELECTION-SCREEN: FUNCTION KEY 1.

* B10: Selection range / Upload file
*---------------------------------------
SELECTION-SCREEN: BEGIN OF BLOCK box1 WITH FRAME TITLE tp_b10.
PARAMETERS:       pa_sel RADIOBUTTON GROUP mod DEFAULT 'X'
                                               USER-COMMAND sel.
PARAMETERS:       pa_upl RADIOBUTTON GROUP mod.
SELECTION-SCREEN: END OF BLOCK box1.

* B20: Selection criteria or Upload file
*---------------------------------------
SELECTION-SCREEN: BEGIN OF BLOCK box2 WITH FRAME TITLE tp_b20.
SELECT-OPTIONS:   so_korr FOR e070-strkorr MODIF ID sel.
PARAMETERS:       pa_str TYPE as4text VISIBLE LENGTH 41
                                      MODIF ID sel.
SELECTION-SCREEN: SKIP 1.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: COMMENT 1(20) tp_c21 MODIF ID sel.
SELECTION-SCREEN: POSITION 30.
SELECT-OPTIONS:   so_user FOR sy-uname DEFAULT sy-uname
                                       MATCHCODE OBJECT user_addr
                                       MODIF ID sel.
SELECTION-SCREEN: PUSHBUTTON 71(5) i_name
                                   USER-COMMAND name
                                   MODIF ID sel.            "#EC NEEDED
SELECTION-SCREEN: END OF LINE.
SELECT-OPTIONS:   so_date FOR e070-as4date MODIF ID sel.
SELECTION-SCREEN: PUSHBUTTON 69(7) i_date
                             USER-COMMAND date
                             MODIF ID sel.                  "#EC NEEDED
SELECT-OPTIONS:   so_proj FOR ctsproject-trkorr MODIF ID sel.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: COMMENT 1(20) tp_c22 MODIF ID upl.
SELECTION-SCREEN: POSITION POS_LOW.
PARAMETERS:       pa_file TYPE localfile MODIF ID upl.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: END OF BLOCK box2.

* B30: Transport Track
*---------------------------------------
SELECTION-SCREEN: BEGIN OF BLOCK box3 WITH FRAME TITLE tp_b30.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: COMMENT 32(15) tp_c34.
SELECTION-SCREEN: COMMENT 50(15) tp_c35.
SELECTION-SCREEN: COMMENT 68(15) tp_c36.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: BEGIN OF LINE.
* C31 - Route
SELECTION-SCREEN: COMMENT 1(20) tp_c31.
SELECTION-SCREEN: POSITION POS_LOW.
PARAMETERS:       pa_dev TYPE sysname DEFAULT 'DEV'.
* C32 - -->
SELECTION-SCREEN: COMMENT 45(3) tp_c32.
SELECTION-SCREEN: POSITION 51.
PARAMETERS:       pa_qas TYPE sysname DEFAULT 'QAS'.
* C33 - -->
SELECTION-SCREEN: COMMENT 63(3) tp_c33 MODIF ID vrs.
SELECTION-SCREEN: POSITION 69.
PARAMETERS:       pa_prd TYPE sysname DEFAULT 'PRD' MODIF ID vrs.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: END OF BLOCK box3.

* B40: Check options
*---------------------------------------
SELECTION-SCREEN: BEGIN OF BLOCK box4 WITH FRAME TITLE tp_b40.
SELECTION-SCREEN: BEGIN OF LINE.
PARAMETERS:       pa_check RADIOBUTTON GROUP rad DEFAULT 'X'
                           USER-COMMAND chk MODIF ID vrs.
SELECTION-SCREEN: COMMENT 4(20)   tp_c46 MODIF ID vrs.
PARAMETERS:       pa_nochk RADIOBUTTON GROUP rad MODIF ID vrs.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: SKIP 1.
SELECTION-SCREEN: BEGIN OF LINE.
PARAMETERS:       pa_noprd AS CHECKBOX DEFAULT 'X' MODIF ID vrs.
* C41 - Use User specific layout
SELECTION-SCREEN: COMMENT 4(63) tp_c40 MODIF ID vrs.
SELECTION-SCREEN: END OF LINE.

SELECTION-SCREEN: BEGIN OF LINE.
PARAMETERS:       pa_user AS CHECKBOX DEFAULT ' ' MODIF ID vrs.
* C41 - Use User specific layout
SELECTION-SCREEN: COMMENT 4(63) tp_c41 MODIF ID vrs.
SELECTION-SCREEN: END OF LINE.

SELECTION-SCREEN: BEGIN OF LINE.
PARAMETERS:       pa_buff AS CHECKBOX DEFAULT 'X' MODIF ID vrs.
* C42 - Skip transport buffer check
SELECTION-SCREEN: COMMENT 4(63) tp_c42 MODIF ID vrs.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: BEGIN OF LINE.
PARAMETERS:       pa_chkky AS CHECKBOX DEFAULT 'X' MODIF ID chk
                           USER-COMMAND key.
* C43 - Check table keys
SELECTION-SCREEN: COMMENT 4(16) tp_c43 MODIF ID chk.
SELECTION-SCREEN: END OF LINE.
*PARAMETERS:       pa_kdate TYPE as4date MODIF ID key.
SELECTION-SCREEN: BEGIN OF LINE.
PARAMETERS:       pa_chd AS CHECKBOX DEFAULT ' ' MODIF ID upl.
* C44  - Reset 'Checked' field
SELECTION-SCREEN: COMMENT 4(16) tp_c44 MODIF ID upl.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: END OF BLOCK box4.

* B50: Exclude from check
*---------------------------------------
SELECTION-SCREEN: BEGIN OF BLOCK box5 WITH FRAME TITLE tp_b50.
*C51 - Objects in the range will not be taken into account when checking
*      the
SELECTION-SCREEN: COMMENT /1(74) tp_c51 MODIF ID chk.
*C52 - transports. Useful to exclude common customizing tables (like
*      SWOTICE for
SELECTION-SCREEN: COMMENT /1(74) tp_c52 MODIF ID chk.
* C53 - workflow or the tables for Pricing procedures).
SELECTION-SCREEN: COMMENT /1(74) tp_c53 MODIF ID chk.
SELECT-OPTIONS:   so_exobj FOR e071-obj_name NO INTERVALS
                                               MODIF ID chk.
SELECTION-SCREEN: END OF BLOCK box5.

* B60 - Overview of used Icons
*---------------------------------------
SELECTION-SCREEN: BEGIN OF BLOCK box6 WITH FRAME TITLE tp_b60.
SELECTION-SCREEN: BEGIN OF LINE.
PARAMETERS:       pa_icon RADIOBUTTON GROUP ico USER-COMMAND ico
                                                MODIF ID vrs.
* C61 - Show
SELECTION-SCREEN: COMMENT 4(6) tp_c61 MODIF ID vrs.
PARAMETERS:       pa_noicn RADIOBUTTON GROUP ico DEFAULT 'X'
                                                 MODIF ID vrs.
* C62 - Hide
SELECTION-SCREEN: COMMENT 14(4) tp_c62 MODIF ID vrs.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: PUSHBUTTON 1(4) p_error USER-COMMAND error
                                          MODIF ID ico.     "#EC NEEDED
* W01 - Transporting to Production will overwrite a newer version!
SELECTION-SCREEN: COMMENT 8(74) tp_w01  MODIF ID ico.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: PUSHBUTTON 1(4) p_ddic USER-COMMAND ddic
                                          MODIF ID ico.     "#EC NEEDED
*W18 - Transport already in Production, but selected for re-import by
*      the user
SELECTION-SCREEN: COMMENT 8(74) tp_w05  MODIF ID ico.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: PUSHBUTTON 1(4) p_warn  USER-COMMAND warn
                                          MODIF ID ico.     "#EC NEEDED
* W17 - Previous transport not transported
SELECTION-SCREEN: COMMENT 8(74) tp_w17  MODIF ID ico.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: PUSHBUTTON 1(4) p_info  USER-COMMAND info
                                          MODIF ID ico.     "#EC NEEDED
*W23 - There is a newer version in Acceptance. Check if it should be
*      moved too
SELECTION-SCREEN: COMMENT 8(74) tp_w23  MODIF ID ico.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: PUSHBUTTON 1(4) p_hint  USER-COMMAND hint
                                          MODIF ID ico.     "#EC NEEDED
*W04 - Previous or newer transport not transported, but is also in the
*      list
SELECTION-SCREEN: COMMENT 8(74) tp_w04  MODIF ID ico.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: BEGIN OF LINE.
SELECTION-SCREEN: PUSHBUTTON 1(4) p_added USER-COMMAND added
                                          MODIF ID ico.     "#EC NEEDED
*W18 - Transport already in Production, but selected for re-import by
*      the user
SELECTION-SCREEN: COMMENT 8(74) tp_w18  MODIF ID ico.
SELECTION-SCREEN: END OF LINE.
SELECTION-SCREEN: END OF BLOCK box6.

*--------------------------------------------------------------------*
* Initialize
*--------------------------------------------------------------------*
INITIALIZATION.

* To be able to use methods on the selection screen
  IF rf_ztct IS NOT BOUND.
    TRY .
        CREATE OBJECT rf_ztct.
      CATCH cx_root INTO rf_root.
        tp_msg = rf_root->get_text( ).
        CONCATENATE 'ERROR:'(038) tp_msg INTO tp_msg SEPARATED BY space.
        MESSAGE tp_msg TYPE 'E'.
    ENDTRY.
  ENDIF.

  MOVE: icon_terminated_position       TO i_name,
        icon_defect                    TO p_error,
        icon_wf_workitem_error         TO p_ddic,
        icon_led_yellow                TO p_warn,
        icon_information               TO p_info,
        icon_hint                      TO p_hint,
        icon_scrap                     TO p_added.

  MOVE: 'Clear'(025)                   TO i_date.
  IF so_date IS INITIAL.
    MOVE: 'Clear'(025)                 TO i_date.
    so_date-sign = 'I'.
    so_date-option = 'BT'.
    so_date-high = sy-datum.
    so_date-low = rf_ztct->go_back_months( im_currdate   = sy-datum
                                           im_backmonths = 6 ).
    APPEND so_date TO so_date.
  ELSE.
    MOVE: 'Def.'(026)                  TO i_date.
    REFRESH so_date.
  ENDIF.

* Set selection texts (to link texts to selection screen):
* This is done to facilitate (love that word...) the copying of this
* program to other environments without losing all the texts.
  tp_b10 = 'Selection range / Upload file'(b10).
  tp_b30 = 'Transport Track'(b30).
  tp_b40 = 'Check options'(b40).
  tp_b50 = 'Exclude from check'(b50).
  tp_b60 = 'Overview of used Icons'(b60).
  tp_c21 = 'User'(c21).
  tp_c22 = 'File name'(c22).
  tp_c31 = 'Route'(c31).
  tp_c32 = '-->'(c32).
  tp_c33 = '-->'(c33).
  tp_c34 = 'Development'(c34).
  tp_c35 = 'Tested in env.'(c35).
  tp_c36 = 'Target env.'(c36).
  tp_c40 = 'Do not select transports already in target environment'(c40).
  tp_c41 = 'Use User specific layout'(c41).
  tp_c42 = 'Skip transport buffer check'(c42).
  tp_c43 = 'Check table keys'(c43).
  tp_c44 = 'Reset `Checked` field'(c44).
  tp_c46 = 'Check ON / Check OFF'(c46).
  tp_c51 = 'Objects in the range will not be taken into account ' &
           'when checking the'(c51).
  tp_c52 = 'transports. Useful to exclude common customizing tables ' &
           '(like SWOTICE for'(c52).
  tp_c53 = 'workflow or the tables for Pricing procedures).'(c53).
  tp_c61 = 'Show'(c61).
  tp_c62 = 'Hide'(c62).
*  tp_w01 = 'Newer version in production!'(w01).
  tp_w01 = 'Newer version in target environment!'(w01).
  tp_w05 = 'Object missing in list and target environment!'(w05).
  tp_w17 = 'Previous transport not transported'(w17).
  tp_w23 = 'Newer version in test environment'(w23).
  tp_w04 = 'All conflicts are dealt with'(w04).
  tp_w18 = 'Marked for re-import to target environment'(w18).

* Create a range table containing all project numbers:
  st_project_trkorrs-sign = 'E'.
  st_project_trkorrs-option = 'EQ'.
  SELECT trkorr FROM ctsproject
                INTO st_project_trkorrs-low.          "#EC CI_SGLSELECT
    APPEND st_project_trkorrs TO ra_project_trkorrs.
  ENDSELECT.

* Get the transport track
  tp_sysname = sy-sysid.
  CALL FUNCTION 'TR_GET_LIST_OF_TARGETS'
    EXPORTING
      iv_src_system    = tp_sysname
    IMPORTING
      et_targets       = ta_targets
    EXCEPTIONS
      tce_config_error = 1
      OTHERS           = 2.
  IF sy-subrc <> 0.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
  ENDIF.
  pa_dev = sy-sysid.
  LOOP AT ta_targets INTO st_target.
    CASE sy-tabix.
      WHEN 1.
        pa_qas = st_target.
      WHEN 2.
        pa_prd = st_target.
    ENDCASE.
  ENDLOOP.

* Move to range:
  st_systems-sign   = 'I'.
  st_systems-option = 'EQ'.
  LOOP AT ta_sapsystems INTO st_sapsystems.
    MOVE st_sapsystems-sysnam TO st_systems-low.
    APPEND st_systems TO ra_systems.
  ENDLOOP.

* Default values for s_exobj. These objects will not be checked!
* Exclude Single values:
  so_exobj-sign   = 'E'.
  so_exobj-option = 'EQ'.
  so_exobj-low    = 'SWOTICE'.  " Index of Frozen DDIC Structures
  APPEND so_exobj TO so_exobj.
  so_exobj-low    = 'TVDIR'.    " View Directory
  APPEND so_exobj TO so_exobj.
  so_exobj-low    = 'TDDAT'.    " Maintenance Areas for Tables
  APPEND so_exobj TO so_exobj.
*--------------------------------------------------------------------*
* Selection screen Checks
*--------------------------------------------------------------------*
AT SELECTION-SCREEN.
  CASE sy-ucomm.
    WHEN 'NAME'.
      IF NOT so_user IS INITIAL.
        REFRESH: so_user.
        CLEAR:   so_user.
        MOVE icon_create_position TO i_name.
      ELSE.
        so_user-option = 'EQ'.
        so_user-sign = 'I'.
        so_user-low = sy-uname.
        APPEND: so_user TO so_user.
        MOVE icon_terminated_position TO i_name.
      ENDIF.
    WHEN 'DATE'.
      IF so_date IS INITIAL.
        MOVE: 'Clear'(025) TO i_date.
        IF so_date[] IS INITIAL.
          so_date-sign = 'I'.
          so_date-option = 'BT'.
          so_date-high = sy-datum.
          so_date-low = rf_ztct->go_back_months( im_currdate   = sy-datum
                                                 im_backmonths = 6 ).
          APPEND so_date TO so_date.
        ENDIF.
      ELSE.
        MOVE: 'Def.'(026) TO i_date.
        REFRESH so_date.
      ENDIF.
  ENDCASE.

AT SELECTION-SCREEN ON pa_dev.
  SELECT SINGLE * FROM tcesyst INTO st_tcesyst WHERE sysname = pa_dev.
  IF sy-subrc <> 0.
    MESSAGE e000(db) DISPLAY LIKE 'E'
                  WITH 'System' pa_dev 'does not exist...'.
  ENDIF.

AT SELECTION-SCREEN ON pa_qas.
  SELECT SINGLE * FROM tcesyst INTO st_tcesyst WHERE sysname = pa_qas.
  IF sy-subrc <> 0.
    MESSAGE e000(db) DISPLAY LIKE 'E'
                  WITH 'System' pa_qas 'does not exist...'.
  ENDIF.

AT SELECTION-SCREEN ON pa_prd.
  SELECT SINGLE * FROM tcesyst INTO st_tcesyst WHERE sysname = pa_prd.
  IF sy-subrc <> 0.
    MESSAGE e000(db) DISPLAY LIKE 'E'
                  WITH 'System' pa_prd 'does not exist...'.
  ENDIF.

AT SELECTION-SCREEN OUTPUT.
* This commented out code can be used to add a function on the toolbar:
  st_smp_dyntxt-text       = 'Information'(027).
  st_smp_dyntxt-icon_id    = rf_ztct->co_info.
  st_smp_dyntxt-icon_text  = 'Info'(024).
  st_smp_dyntxt-quickinfo  = 'General Info'(028).
  st_smp_dyntxt-path       = 'I'.
  sscrfields-functxt_01 = st_smp_dyntxt.

  LOOP AT SCREEN.
    CASE screen-group1.
      WHEN 'SEL'.
        IF pa_sel = 'X'.
          screen-active = '1'.
          tp_b20 = 'Selection criteria'(b21).
        ELSE.
          screen-active = '0'.
          tp_b20 = 'File upload'(b22).
        ENDIF.
        MODIFY SCREEN.
      WHEN 'CHK'.
        IF pa_check = 'X'.
          screen-active = '1'.
        ELSE.
          screen-active = '0'.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'DIC'.
        IF pa_check = 'X'.
          screen-active = '1'.
        ELSE.
          screen-active = '0'.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'KEY'.
        IF pa_chkky = 'X' AND pa_check = 'X'.
          screen-active = '1'.
        ELSE.
          screen-active = '0'.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'UPL'.
        IF pa_upl = 'X'.
          screen-active = '1'.
        ELSE.
          screen-active = '0'.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'ICO'.
        IF pa_icon = 'X'.
          screen-active = '1'.
        ELSE.
          screen-active = '0'.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'GRY'.
        screen-input = '0'.
        MODIFY SCREEN.
    ENDCASE.
  ENDLOOP.

* If the user range is initial (removed manually), set the correct Icon:
AT SELECTION-SCREEN ON so_user.
  IF so_user[] IS INITIAL.
    MOVE icon_create_position TO i_name.
  ENDIF.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR pa_file.
  rf_ztct->get_filename( IMPORTING ex_file = pa_file ).

*--------------------------------------------------------------------*
*       CLASS lcl_eventhandler_ztct IMPLEMENTATION
*--------------------------------------------------------------------*
CLASS lcl_eventhandler_ztct IMPLEMENTATION.

  METHOD on_function_click.
    TYPES: BEGIN OF lty_sval.
            INCLUDE TYPE sval.
    TYPES: END OF lty_sval.
    TYPES: lty_field TYPE STANDARD TABLE OF lty_sval.
    DATA: ra_transports_to_add TYPE RANGE OF e070-trkorr,
          st_transports_to_add LIKE LINE OF ra_transports_to_add.
    DATA: ta_excluded_objects  TYPE RANGE OF trobj_name.
    DATA: ls_excluded_objects  LIKE LINE  OF ta_excluded_objects.
* Global data declarations:
    DATA: lp_title            TYPE string.
    DATA: lp_filename         TYPE string.
    DATA: lp_file             TYPE localfile.
    DATA: lt_fields           TYPE lty_field. "ty_sval.
    DATA: ls_fields           TYPE sval.
    DATA: lp_tabix            TYPE sytabix.
    DATA: lr_selections       TYPE REF TO cl_salv_selections.
    DATA: lp_localfile        TYPE localfile.
    DATA: lp_filelength       TYPE i.
    DATA: ls_row              TYPE int4.
    DATA: lp_row_found        TYPE abap_bool.
    DATA: lp_return           TYPE c.
*   Selected rows
    DATA: lt_rows             TYPE salv_t_row.
    DATA: ls_cell             TYPE salv_s_cell.
    DATA: lp_path             TYPE string.
    DATA: lp_fullpath         TYPE string.
    DATA: lp_result           TYPE i.
    DATA: lp_desktop          TYPE string.
    DATA: lp_timestamp        TYPE tzntstmps.
    DATA: lp_default_filename TYPE string.
    DATA: lp_question         TYPE string.
    DATA: lp_answer           TYPE char01.

    FIELD-SYMBOLS: <rf_ref_table> TYPE REF TO cl_salv_table.

*   Which popup are we displaying? Conflicts or Table keys?
    IF rf_conflicts IS BOUND.
      ASSIGN rf_conflicts TO <rf_ref_table>.
    ELSEIF rf_table_keys IS BOUND.
      ASSIGN rf_table_keys TO <rf_ref_table>.
    ELSE.
      ASSIGN rf_table TO <rf_ref_table>.
    ENDIF.

*   Get current row
    IF e_salv_function = 'GOON' OR e_salv_function = 'ABR'.
      lr_selections = <rf_ref_table>->get_selections(  ).
      lt_rows = lr_selections->get_selected_rows( ).
      ls_cell = lr_selections->get_current_cell( ).
    ELSE.
      lr_selections = <rf_ref_table>->get_selections(  ).
      lt_rows = lr_selections->get_selected_rows( ).
      ls_cell = lr_selections->get_current_cell( ).
      READ TABLE rf_ztct->main_list INTO  rf_ztct->main_list_line
                                    INDEX ls_cell-row.
    ENDIF.
    CASE e_salv_function.
      WHEN 'GOON'.
        IF rf_conflicts IS BOUND.
          rf_conflicts->close_screen( ).
*         Move the conflicts to a range. The transports in this range will
*         be added to the main list:
          REFRESH: ra_transports_to_add.
          rf_ztct->set_building_conflict_popup( abap_false ).
          CLEAR: st_transports_to_add.
          st_transports_to_add-sign = 'I'.
          st_transports_to_add-option = 'EQ'.
*         If row(s) are selected, use the table
          LOOP AT lt_rows INTO ls_row.
            READ TABLE rf_ztct->conflicts INTO  rf_ztct->conflict_line
                                          INDEX ls_row.
            st_transports_to_add-low = rf_ztct->conflict_line-trkorr.
            APPEND st_transports_to_add TO ra_transports_to_add.
          ENDLOOP.
*         Rows MUST be selected, take the current cell instead
          IF lt_rows[] IS INITIAL.
            MESSAGE i000(db) WITH 'No rows selected: No transports will be added'(m06).
          ENDIF.
          IF ra_transports_to_add[] IS NOT INITIAL.
            rf_ztct->get_added_objects( EXPORTING im_to_add = ra_transports_to_add
                                        IMPORTING ex_to_add = rf_ztct->add_to_main ).
            rf_ztct->get_additional_tp_info( CHANGING ch_table = rf_ztct->add_to_main ).
            rf_ztct->add_to_list( EXPORTING im_to_add = rf_ztct->add_to_main
                                  IMPORTING ex_main   = rf_ztct->main_list ).
*         After the transports have been added, check if there are added
*         transports that are already in prd. If so, make them visible by
*         changing the prd icon to co_scrap.
            LOOP AT rf_ztct->main_list INTO rf_ztct->main_list_line
                                       WHERE prd    = rf_ztct->co_okay
                                       AND   trkorr IN ra_transports_to_add.
              rf_ztct->main_list_line-prd = rf_ztct->co_scrap.
              MODIFY rf_ztct->main_list FROM rf_ztct->main_list_line.
            ENDLOOP.
*         After the transports have been added, we need to check again
            rf_ztct->flag_same_objects( IMPORTING ex_main_list = rf_ztct->main_list ).
            rf_ztct->check_for_conflicts( CHANGING ch_main_list = rf_ztct->main_list ).
            rf_ztct->refresh_alv( ).                   "Refresh the ALV
          ENDIF.
          FREE rf_conflicts.
        ELSE.
*         If row(s) are selected, use the table
          rf_table_keys->close_screen( ).
          LOOP AT lt_rows INTO ls_row.
            READ TABLE rf_ztct->table_keys INTO rf_ztct->table_keys_line
                                           INDEX ls_row.
*           Add all tables that were NOT selected to the exclusion range
            IF sy-subrc <> 0.
              ls_excluded_objects-sign   = 'E'.
              ls_excluded_objects-option = 'EQ'.
              ls_excluded_objects-low    = rf_ztct->table_keys_line-tabname.
              APPEND ls_excluded_objects TO ta_excluded_objects.
            ENDIF.
          ENDLOOP.
*         If user pressed cancel (Add all tables, do not check any)
          IF lt_rows[] IS INITIAL.
            LOOP AT rf_ztct->table_keys INTO  rf_ztct->table_keys_line.
              ls_excluded_objects-sign   = 'E'.
              ls_excluded_objects-option = 'EQ'.
              ls_excluded_objects-low    = rf_ztct->table_keys_line-tabname.
              APPEND ls_excluded_objects TO ta_excluded_objects.
            ENDLOOP.
            MESSAGE i000(db) WITH 'No rows selected: Table keys will ' &
                                  'not be checked'(m07).
            rf_ztct->check_tabkeys = abap_false.
          ENDIF.
          FREE rf_table_keys.
        ENDIF.
      WHEN 'ABR'.
        IF rf_table_keys IS BOUND.
          rf_table_keys->close_screen( ).
*         If user pressed cancel (Add all tables, do not check any)
          LOOP AT rf_ztct->table_keys INTO  rf_ztct->table_keys_line.
            ls_excluded_objects-sign   = 'E'.
            ls_excluded_objects-option = 'EQ'.
            ls_excluded_objects-low    = rf_ztct->table_keys_line-tabname.
            APPEND ls_excluded_objects TO ta_excluded_objects.
          ENDLOOP.
          MESSAGE i000(db) WITH 'Cancelled: Table keys will ' &
                                'not be checked'(m09).
          FREE rf_table_keys.
          rf_ztct->check_tabkeys = abap_false.
        ELSE.
          rf_conflicts->close_screen( ).
          FREE rf_conflicts.
        ENDIF.
      WHEN 'RECHECK'.
        rf_ztct->set_building_conflict_popup( abap_false ).
        rf_ztct->refresh_import_queues( ).
        rf_ztct->flag_for_process( EXPORTING rows = lt_rows
                                             cell = ls_cell ).
        rf_ztct->add_table_keys_to_list( IMPORTING table = rf_ztct->main_list ).
        rf_ztct->get_additional_tp_info( CHANGING ch_table = rf_ztct->main_list ).
        rf_ztct->flag_same_objects( IMPORTING ex_main_list = rf_ztct->main_list ).
        rf_ztct->check_for_conflicts( CHANGING ch_main_list = rf_ztct->main_list ).
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
      WHEN 'DDIC'.
        IF rf_ztct->where_used[] IS INITIAL.
          lp_question = 'This will take approx. 5-15 minutes... Continue?'(041).
        ELSE.
          lp_question = 'This has already been done. Do again?'(042).
        ENDIF.

        CALL FUNCTION 'POPUP_TO_CONFIRM'
          EXPORTING
            titlebar              = 'Runtime Alert'(039)
            text_question         = lp_question
            text_button_1         = 'Yes'(037)
            icon_button_1         = 'ICON_OKAY'
            text_button_2         = 'No'(043)
            icon_button_2         = 'ICON_CANCEL'
            default_button        = '2'
            display_cancel_button = ' '
*           START_COLUMN          = 25
*           START_ROW             = 6
          IMPORTING
            answer                = lp_answer
          EXCEPTIONS
            text_not_found        = 0
            OTHERS                = 0.
        IF sy-subrc <> 0.
* Implement suitable error handling here
        ENDIF.
        IF lp_answer = '1'.
          rf_ztct->check_ddic = abap_true.
          rf_ztct->set_ddic_objects( ).
          rf_ztct->set_where_used( ).
        ENDIF.
        rf_ztct->do_ddic_check( CHANGING ch_main_list = rf_ztct->main_list ).
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
        MESSAGE i000(db) WITH 'Data Dictionary check finished...'(m15).
      WHEN '&ADD'. "Button clicked
        rf_ztct->set_building_conflict_popup(  ).
*       Here, we want to give the option to the user to select the
*       transports to be added. Display a popup with the option to select the
*       transports to be added with checkboxes.
        rf_ztct->flag_for_process( EXPORTING rows = lt_rows
                                             cell = ls_cell ).
        rf_ztct->flag_same_objects( IMPORTING ex_main_list = rf_ztct->main_list ).
        rf_ztct->check_for_conflicts( CHANGING ch_main_list = rf_ztct->main_list ).
        rf_ztct->build_conflict_popup( rows = lt_rows
                                       cell = ls_cell ).
      WHEN '&ADD_TP'.
        REFRESH: lt_fields.
        CLEAR:   ls_fields.
        ls_fields-tabname   = 'E070'.
        ls_fields-fieldname = 'TRKORR'.
        APPEND ls_fields TO lt_fields.
        CALL FUNCTION 'POPUP_GET_VALUES_DB_CHECKED'
          EXPORTING
            popup_title     = 'Selected transports'(t01)
          IMPORTING
            returncode      = lp_return
          TABLES
            fields          = lt_fields
          EXCEPTIONS
            error_in_fields = 1
            OTHERS          = 2.
        CASE sy-subrc.
          WHEN 1.
            MESSAGE e000(db) WITH 'ERROR: ERROR_IN_FIELDS'(m08).
          WHEN 2.
            MESSAGE e000(db) WITH 'Error occurred'(029).
        ENDCASE.
*       Exit if cancelled:
        CHECK lp_return <> 'A'.
*       Move the conflicts to a range. The transports in this range will
*       be added to the main list:
        REFRESH: ra_transports_to_add.
        CLEAR:   st_transports_to_add.
        st_transports_to_add-sign = 'I'.
        st_transports_to_add-option = 'EQ'.
        READ TABLE lt_fields INTO ls_fields INDEX 1.
        CHECK NOT ls_fields-value IS INITIAL.
*       Is it already in the list?
        READ TABLE rf_ztct->main_list WITH KEY trkorr = ls_fields-value(20)
                                        TRANSPORTING NO FIELDS.
        CHECK sy-subrc <> 0.
*       Add transport number to the internal table to add:
        st_transports_to_add-low = ls_fields-value.
        APPEND st_transports_to_add TO ra_transports_to_add.
        rf_ztct->get_added_objects( EXPORTING im_to_add = ra_transports_to_add
                                      IMPORTING ex_to_add = rf_ztct->add_to_main ).
        rf_ztct->get_additional_tp_info( CHANGING ch_table = rf_ztct->add_to_main ).
        rf_ztct->add_to_list( EXPORTING im_to_add = rf_ztct->add_to_main
                                IMPORTING ex_main   = rf_ztct->main_list ).
*       After the transports have been added, check if there are added
*       transports that are already in prd. If so, make them visible by
*       changing the prd icon to co_scrap.
        LOOP AT rf_ztct->main_list INTO  rf_ztct->main_list_line
                             WHERE prd    = rf_ztct->co_okay
                             AND   trkorr IN ra_transports_to_add.
          rf_ztct->main_list_line-prd = rf_ztct->co_scrap.
          MODIFY rf_ztct->main_list FROM rf_ztct->main_list_line.
        ENDLOOP.
*       Unfortunately, after the transports have been added, we need to
*       check again...
        rf_ztct->flag_same_objects( IMPORTING ex_main_list = rf_ztct->main_list ).
        rf_ztct->check_for_conflicts( CHANGING ch_main_list = rf_ztct->main_list ).
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
      WHEN '&ADD_FILE'.
        rf_ztct->clear_flags( ).
        rf_ztct->get_filename( IMPORTING ex_file = lp_localfile ).
        MOVE lp_localfile TO lp_filename.
        rf_ztct->gui_upload( EXPORTING im_filename      = lp_filename
                             IMPORTING ex_tab_delimited = rf_ztct->tab_delimited ).
        rf_ztct->check_for_conflicts( CHANGING ch_main_list = rf_ztct->main_list ).
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
      WHEN '&DEL'.                                "Button clicked
*       Mark all records for the selected transport(s)
        rf_ztct->clear_flags( ).
        rf_ztct->mark_all_tp_records( EXPORTING im_cell = ls_cell
                                      CHANGING  im_rows = lt_rows ).
        rf_ztct->flag_for_process( EXPORTING rows = lt_rows
                                             cell = ls_cell ).
        rf_ztct->flag_same_objects( IMPORTING ex_main_list = rf_ztct->main_list ).
        rf_ztct->delete_tp_from_list( EXPORTING rows = lt_rows
                                                cell = ls_cell ).
        rf_ztct->check_for_conflicts( CHANGING ch_main_list = rf_ztct->main_list ).
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
      WHEN '&IMPORT'. "Button clicked
*       Re-transport a request (transport already in production)
        rf_ztct->clear_flags( ).
        rf_ztct->flag_for_process( EXPORTING rows = lt_rows
                                               cell = ls_cell ).
        REFRESH: ra_transports_to_add.
        CLEAR:   st_transports_to_add.
        st_transports_to_add-sign = 'I'.
        st_transports_to_add-option = 'EQ'.
        LOOP AT rf_ztct->main_list INTO  rf_ztct->main_list_line
                                     WHERE flag = 'X'
                                     AND   prd  = rf_ztct->co_okay.
          st_transports_to_add-low = rf_ztct->main_list_line-trkorr.
          APPEND st_transports_to_add TO ra_transports_to_add.
        ENDLOOP.
        IF ra_transports_to_add IS INITIAL.
          MESSAGE i000(db) WITH 'No records selected that can be re-imported'(m11).
          EXIT.
        ENDIF.
        LOOP AT rf_ztct->main_list INTO rf_ztct->main_list_line
                                     WHERE trkorr IN ra_transports_to_add.
          rf_ztct->main_list_line-flag = 'X'.
          rf_ztct->main_list_line-prd  = rf_ztct->co_scrap.
          MODIFY rf_ztct->main_list FROM rf_ztct->main_list_line.
        ENDLOOP.
        rf_ztct->flag_same_objects( IMPORTING ex_main_list = rf_ztct->main_list ).
        rf_ztct->check_for_conflicts( CHANGING ch_main_list = rf_ztct->main_list ).
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
      WHEN '&DOC'. "Button clicked
        MOVE rf_ztct->main_list_line-trkorr TO tp_dokl_object.
        rf_ztct->docu_call( EXPORTING im_object = tp_dokl_object ).
        rf_ztct->check_documentation( EXPORTING im_trkorr = rf_ztct->main_list_line-trkorr
                                        CHANGING  ch_table  = rf_ztct->main_list ).
      WHEN '&PREP_XLS'.
        CHECK rf_table_xls IS NOT BOUND.
        rf_ztct->display_excel( EXPORTING im_table = rf_ztct->main_list ).
      WHEN '&SAVE'.
*       Build header
        rf_ztct->main_to_tab_delimited( EXPORTING im_main_list     = rf_ztct->main_list
                                        IMPORTING ex_tab_delimited = rf_ztct->tab_delimited ).
* Finding desktop
        CALL METHOD cl_gui_frontend_services=>get_desktop_directory
          CHANGING
            desktop_directory    = lp_desktop
          EXCEPTIONS
            cntl_error           = 1
            error_no_gui         = 2
            not_supported_by_gui = 3
            OTHERS               = 4.
        IF sy-subrc <> 0.
          MESSAGE e001(00) WITH
              'Desktop not found'(008).
        ENDIF.

        CONVERT DATE sy-datum TIME sy-uzeit
          INTO TIME STAMP lp_timestamp TIME ZONE sy-zonlo.
        lp_default_filename = lp_timestamp.
        CONCATENATE 'ZTCT-' lp_default_filename INTO lp_default_filename.

        lp_title = 'Save Transportlist'(009).
        CALL METHOD cl_gui_frontend_services=>file_save_dialog
          EXPORTING
            window_title         = lp_title
            default_extension    = 'TXT'
            default_file_name    = lp_default_filename
            initial_directory    = lp_desktop
          CHANGING
            filename             = lp_filename
            path                 = lp_path
            fullpath             = lp_fullpath
          EXCEPTIONS
            cntl_error           = 1
            error_no_gui         = 2
            not_supported_by_gui = 3
            OTHERS               = 4.
        IF sy-subrc <> 0.
          MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
                     WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
        ENDIF.

*       Display save dialog window
        CALL METHOD cl_gui_frontend_services=>gui_download
          EXPORTING
            filename                = lp_fullpath
            filetype                = 'ASC'
          IMPORTING
            filelength              = lp_filelength
          CHANGING
            data_tab                = rf_ztct->tab_delimited
          EXCEPTIONS
            file_write_error        = 1
            no_batch                = 2
            gui_refuse_filetransfer = 3
            invalid_type            = 4
            no_authority            = 5
            unknown_error           = 6
            header_not_allowed      = 7
            separator_not_allowed   = 8
            filesize_not_allowed    = 9
            header_too_long         = 10
            dp_error_create         = 11
            dp_error_send           = 12
            dp_error_write          = 13
            unknown_dp_error        = 14
            access_denied           = 15
            dp_out_of_memory        = 16
            disk_full               = 17
            dp_timeout              = 18
            file_not_found          = 19
            dataprovider_exception  = 20
            control_flush_error     = 21
            not_supported_by_gui    = 22
            error_no_gui            = 23
            OTHERS                  = 24.
        CASE sy-subrc.
          WHEN 0.
          WHEN OTHERS.
            MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
                       WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
        ENDCASE.
      WHEN '&NCONF'.
        CLEAR: lp_row_found.
        lp_tabix = ls_cell-row + 1.
        LOOP AT rf_ztct->main_list INTO rf_ztct->main_list_line FROM lp_tabix.
          IF lp_row_found IS INITIAL AND
            ( rf_ztct->main_list_line-warning_rank >= rf_ztct->co_info_rank ).
            ls_cell-row = sy-tabix.
            ls_cell-columnname = 'WARNING_LVL'.
            lr_selections->set_current_cell( ls_cell ).
            lp_row_found = abap_true.
          ENDIF.
        ENDLOOP.
        IF lp_row_found IS INITIAL.
          LOOP AT rf_ztct->main_list INTO rf_ztct->main_list_line.
            IF lp_row_found IS INITIAL AND
             ( rf_ztct->main_list_line-warning_rank >= rf_ztct->co_info_rank ).
              ls_cell-row = sy-tabix.
              ls_cell-columnname = 'WARNING_LVL'.
              lr_selections->set_current_cell( ls_cell ).
              lp_row_found = abap_true.
            ENDIF.
          ENDLOOP.
          IF lp_row_found IS INITIAL.
            MESSAGE i000(db) WITH 'No next conflict found'(021).
          ENDIF.
        ENDIF.
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
    ENDCASE.
  ENDMETHOD.                    "on_function_click

  METHOD on_double_click.
    DATA: lr_selections      TYPE REF TO cl_salv_selections.
*   Selected rows
    DATA: lt_rows    TYPE salv_t_row.
    DATA: ls_cell    TYPE salv_s_cell.

    lr_selections = rf_table->get_selections(  ).
    lt_rows = lr_selections->get_selected_rows( ).
    ls_cell = lr_selections->get_current_cell( ).

*   Only display the details when the list is the MAIN list (Object level
* not when the list is on Header level (XLS)
    IF rf_table_xls IS BOUND.
      EXIT.
    ELSE.
      READ TABLE rf_ztct->main_list     INTO rf_ztct->main_list_line INDEX row.
    ENDIF.
    CASE column.
      WHEN 'TRKORR'.
        rf_ztct->display_transport( EXPORTING im_trkorr = rf_ztct->main_list_line-trkorr ).
      WHEN 'AS4USER'.
        rf_ztct->display_user( EXPORTING im_user = rf_ztct->main_list_line-as4user ).
      WHEN 'CHECKED_BY'.
        rf_ztct->display_user( EXPORTING im_user = rf_ztct->main_list_line-checked_by ).
*     Documentation
      WHEN 'INFO'.
        rf_ztct->display_docu( EXPORTING im_trkorr = rf_ztct->main_list_line-trkorr ).
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
      WHEN 'WARNING_LVL'.
*       Display popup with the conflicting transports/objects
        IF rf_ztct->main_list_line-warning_lvl IS NOT INITIAL.
          rf_ztct->build_conflict_popup( rows = lt_rows
                                         cell = ls_cell ).
          rf_ztct->refresh_alv( ).                 "Refresh the ALV
        ENDIF.
      WHEN OTHERS.
    ENDCASE.
  ENDMETHOD.                                       "on_double_click

  METHOD on_double_click_popup.
    DATA: lr_selections      TYPE REF TO cl_salv_selections.
*   Selected rows
    DATA: lt_rows    TYPE salv_t_row.
    DATA: ls_cell    TYPE salv_s_cell.

    lr_selections = rf_table->get_selections(  ).
    lt_rows = lr_selections->get_selected_rows( ).
    ls_cell = lr_selections->get_current_cell( ).

    READ TABLE rf_ztct->conflicts INTO rf_ztct->conflict_line INDEX row.
    CASE column.
      WHEN 'TRKORR'.
        rf_ztct->display_transport( EXPORTING im_trkorr = rf_ztct->conflict_line-trkorr ).
      WHEN 'AS4USER'.
        rf_ztct->display_user( EXPORTING im_user = rf_ztct->conflict_line-as4user ).
      WHEN 'CHECKED_BY'.
        rf_ztct->display_user( EXPORTING im_user = rf_ztct->conflict_line-checked_by ).
*     Documentation
      WHEN 'INFO'.
        rf_ztct->display_docu( EXPORTING im_trkorr = rf_ztct->conflict_line-trkorr ).
        rf_ztct->refresh_alv( ).                   "Refresh the ALV
      WHEN OTHERS.
    ENDCASE.
  ENDMETHOD.                                       "on_double_click

  METHOD on_link_click.
    FIELD-SYMBOLS: <rf_ref_table> TYPE REF TO cl_salv_table.
*   Which table are we displaying? Object level or Header level (XLS)?
    IF rf_table_xls IS BOUND.
      READ TABLE rf_ztct->main_list_xls INTO rf_ztct->main_list_line INDEX row.
    ELSE.
      READ TABLE rf_ztct->main_list     INTO rf_ztct->main_list_line INDEX row.
    ENDIF.
    CASE column.
      WHEN 'TRKORR'.
        rf_ztct->display_transport( EXPORTING im_trkorr = rf_ztct->main_list_line-trkorr ).
      WHEN 'OBJ_NAME'.
        CALL FUNCTION 'TR_OBJECT_JUMP_TO_TOOL'
          EXPORTING
            iv_pgmid    = rf_ztct->main_list_line-pgmid
            iv_object   = rf_ztct->main_list_line-object
            iv_obj_name = rf_ztct->main_list_line-obj_name
            iv_action   = 'SHOW'
          EXCEPTIONS
            OTHERS      = 1.
        IF sy-subrc <> 0.
          MESSAGE i000(db) WITH 'Object cannot be displayed...'(m14).
        ENDIF.
      WHEN OTHERS.
    ENDCASE.
  ENDMETHOD.                                       "on_link_click

  METHOD on_link_click_popup.
    READ TABLE rf_ztct->conflicts INTO rf_ztct->conflict_line INDEX row.
    CASE column.
      WHEN 'TRKORR'.
        rf_ztct->display_transport( EXPORTING im_trkorr = rf_ztct->conflict_line-trkorr ).
      WHEN OTHERS.
    ENDCASE.
  ENDMETHOD.                                       "on_link_click_popup

ENDCLASS.                    "lcl_eventhandler_ztct IMPLEMENTATION

*--------------------------------------------------------------------*
*       CLASS lcl_ztct IMPLEMENTATION
*--------------------------------------------------------------------*
CLASS lcl_ztct IMPLEMENTATION.

  METHOD constructor.
    DATA: ra_project_trkorrs            TYPE RANGE OF trkorr.
    DATA: st_project_trkorrs            LIKE LINE OF ra_project_trkorrs.

    lp_alert0_text = 'Log couldn''t be read or TP not released'(w16).
    lp_alert1_text = 'Transport not released'(w19).
    lp_alert2_text = 'Release started'(w20).
    lp_alert3_text = 'Transport not in Transport Buffer'(m12).
    lp_hint1_text  = 'Newer version in Acceptance, but in list'(w22).
    lp_hint2_text  = 'All conflicts are dealt with by the list'(w04).
    lp_hint3_text  = 'Couldn''t read log, but object in list'(w21).
    lp_hint4_text  = 'Overwrites version(s), newer version in list'(w11).
    lp_warn_text   = 'Previous transport not transported'(w17).
    lp_error_text  = 'Newer version in production!'(w01).
    lp_ddic_text   = 'Uses object not in list or production'(w03).
    lp_info_text   = 'Newer version in test environment'(w23).
    lp_fail_text   = 'Transport not possible'(w24).
*   Create a range table containing all project transport numbers.
*   When selecting transports, these can be skipped.
    st_project_trkorrs-sign   = 'I'.
    st_project_trkorrs-option = 'EQ'.
    SELECT trkorr FROM ctsproject
                  INTO st_project_trkorrs-low.        "#EC CI_SGLSELECT
      APPEND st_project_trkorrs TO me->project_trkorrs.
    ENDSELECT.
*   Ensure that the range cannot be empty
    IF me->project_trkorrs IS INITIAL.
      st_project_trkorrs-low = 'DUMMY'.               "#EC CI_SGLSELECT
      APPEND st_project_trkorrs TO me->project_trkorrs.
    ENDIF.
  ENDMETHOD.                    "constructor

  METHOD execute.
    DATA: lp_cancelled TYPE abap_bool.
    IF process_type = 1.
      me->get_data( EXPORTING im_trkorr_range = trkorr_range ).
      me->get_additional_tp_info( CHANGING ch_table = me->main_list ).
*     First selection: If the flag to exclude transport that are already
*     in production is set, remove all these transports from the main
*     list.
      IF skiplive IS NOT INITIAL.
        me->remove_tp_in_prd( ).
      ENDIF.
*     Table checks not possible for version checking.
      IF process_type = 1.
        me->build_table_keys_popup( ).
        me->add_table_keys_to_list( IMPORTING table = me->main_list ).
      ENDIF.
* Reason to check data dictionary objects:
* If objects in the transport list contain DDIC objects that do NOT
* exist in production and do NOT exist in the transport list, errors
* (DUMPS) will happen when the transports are moved to production.
* Checking steps:
*   1. Get all Z-objects in tables DD01L, DD02L and DD04L (Domains,
*      Tables, Elements)
*   2. Get all transports from E071 containing these objects
*   3. Store the link between Transports and Objects in attribute WHERE_USED
*   4. Remove from the table all records for objects/transports that have
*       been transported to production
*   5. Execute a Where-Used on all remaining objects
*   6. If there are Objects in the main transport list, that are ALSO in
*     the Where-Used list then THE TRANSPORT CANNOT GO TO PRODUCTION!
      IF check_ddic = abap_true.
        me->prepare_ddic_check( ).
      ENDIF.
      me->check_for_conflicts( CHANGING ch_main_list = me->main_list ).
    ELSE.
      me->gui_upload( EXPORTING im_filename  = filename
                      IMPORTING ex_cancelled = lp_cancelled ).
      IF lp_cancelled = abap_true.
        EXIT.
      ENDIF.
    ENDIF.
    me->set_color( ).
    me->alv_init( ).
    me->alv_set_properties( EXPORTING im_table = rf_table ).
    me->alv_set_tooltips( EXPORTING im_table = rf_table ).
    me->alv_output( ).
  ENDMETHOD.                    "execute

  METHOD get_data.
    me->refresh_import_queues( ).
    me->get_main_transports( EXPORTING im_trkorr_range = im_trkorr_range ).
  ENDMETHOD.                    "get_data

  METHOD: get_tp_prefix.
    IF me->prefix IS INITIAL.
*     Build transport prefix
      IF im_dev IS SUPPLIED.
        set_tp_prefix( EXPORTING im_dev = im_dev ).
      ELSE.
        set_tp_prefix( ).
      ENDIF.
    ENDIF.
    re_tp_prefix = me->prefix.
  ENDMETHOD.                    "set_tp_prefix

  METHOD: set_tp_prefix.
*   Build transport prefix:
    IF im_dev IS SUPPLIED.
      CONCATENATE im_dev 'K%' INTO me->prefix.
    ELSE.
      CONCATENATE sy-sysid 'K%' INTO me->prefix.
    ENDIF.
  ENDMETHOD.                    "set_tp_prefix

  METHOD: refresh_import_queues.
    CALL FUNCTION 'TMS_MGR_REFRESH_IMPORT_QUEUES'.
  ENDMETHOD.                    "refresh_import_queues

  METHOD: flag_for_process.
    DATA: ra_trkorr TYPE RANGE OF trkorr.
    DATA: ls_trkorr LIKE LINE OF ra_trkorr.
    DATA: ls_row      TYPE int4.
    IF rows IS INITIAL AND cell IS INITIAL.
      MESSAGE i000(db) WITH 'Please select records or put the cursor on a row'(m10).
      EXIT.
    ENDIF.
*   First clear all the flags:
    me->clear_flags( ).
*   If the DDIC check is OFF, but there ARE DDIC warnings in the list,
*   then we need to flag these records to be checked. If that is not
*   done then the DDIC warning icon would stay, even if the missing
*   DDIC object would be added to the list...
    IF me->check_ddic = abap_false.
      LOOP AT me->main_list INTO  me->main_list_line
                            WHERE warning_lvl = co_ddic.
        me->main_list_line-flag = abap_true.
        MODIFY me->main_list FROM me->main_list_line INDEX sy-tabix TRANSPORTING flag.
      ENDLOOP.
    ENDIF.
*   If row(s) are selected, use the table
    LOOP AT rows INTO ls_row.
      me->main_list_line-flag = abap_true.
      MODIFY me->main_list FROM me->main_list_line INDEX ls_row TRANSPORTING flag.
    ENDLOOP.
*   If no rows were selected, take the current cell instead
    IF sy-subrc <> 0.
      READ TABLE me->main_list INTO me->main_list_line INDEX cell-row.
      me->main_list_line-flag = abap_true.
      MODIFY me->main_list FROM me->main_list_line INDEX cell-row TRANSPORTING flag.
    ENDIF.
  ENDMETHOD.                    "flag_for_process

  METHOD: check_for_conflicts.
    DATA: ls_ddic_conflict_info TYPE ty_request_details.
    DATA: ta_stms_wbo_requests TYPE TABLE OF stms_wbo_request,
          st_stms_wbo_requests TYPE stms_wbo_request.
    DATA: lp_counter           TYPE i.
    DATA: lp_tabix             TYPE sytabix.
    DATA: lp_return            TYPE c.
    DATA: lp_exit              TYPE abap_bool.
    DATA: ls_main              TYPE ty_request_details.
    DATA: ls_line_temp         TYPE ty_request_details.
    DATA: lt_newer_transports  TYPE tt_request_details.
    DATA: lt_older_transports  TYPE tt_request_details.
    DATA: ls_newer_line        TYPE ty_request_details.
    DATA: ls_older_line        TYPE ty_request_details.
    DATA: lp_domnam            TYPE char10.
    DATA: lp_highest_lvl       TYPE icon_d.
    DATA: lp_highest_rank      TYPE numc4.
    DATA: lp_highest_text      TYPE text74.
    DATA: lp_highest_col       TYPE lvc_t_scol.
    DATA: lp_target            TYPE tmssysnam.
    DATA: lp_obj_name          TYPE trobj_name.
    REFRESH: me->conflicts.
    CLEAR:   me->conflict_line,
             me->total.
    CHECK me->check_flag = abap_true.
*   For each transports, all the objects in the transport will be checked.
*   If there is a newer version of an object in prd, then a warning will
*   be displayed. Also if a newer version that was in prd was actually
*   overwritten or if an object could not be checked.
*   Total for progress indicator: How many will be checked?
    CLEAR: lp_counter.
    LOOP AT ch_main_list INTO ls_main WHERE prd <> co_okay
                                      AND   dev <> co_error
                                      AND   flag = abap_true.
      me->total = me->total + 1.
    ENDLOOP.

*   Check each object in the main list, that has been flagged (also allow
*   checking of transports in prd, those may have been added for transport
*   again):
    LOOP AT ch_main_list INTO ls_main WHERE prd  <> co_okay
                                      AND   dev  <> co_error
                                      AND   flag =  abap_true.
      CLEAR: me->conflict_line.
      CLEAR: ls_main-warning_lvl,
             ls_main-warning_rank,
             ls_main-warning_txt.
      lp_tabix = sy-tabix.
*     Show the progress indicator
      lp_counter = lp_counter + 1.
      me->progress_indicator( EXPORTING im_counter = lp_counter
                                        im_object  = ls_main-obj_name
                                        im_total   = me->total
                                        im_text    = 'Objects checked'(011)
                                        im_flag    = ' ' ).
*     The CHECKED flag is useful to check if the check has been carried
*     out. On the selection screen, you can choose to clear the flags
*     (which can be useful if the file is old and needs to be rechecked)
*     This flag will aid the user when the user checks the list in
*     stages (Example: Half today and the other half tomorrow).
*     st_main-checked is set here to 'X'. It will be updated later when
*     the check has been executed and the main list updated with the
*     change.
      ls_main-checked = co_checked.
      MODIFY ch_main_list FROM ls_main TRANSPORTING checked.
*     Check for documentation:
      me->check_documentation( EXPORTING im_trkorr = ls_main-trkorr
                               CHANGING  ch_table  = ch_main_list ).
*     The check is only relevant if transport is in QAS or DEV! Check is
*     skipped for the transports, already in prd.
      IF ls_main-qas = co_okay.
        MOVE me->prd_system TO lp_target.
      ENDIF.
*     Now check the object:
      me->get_tps_for_same_object( EXPORTING im_line  = ls_main
                                   IMPORTING ex_newer = lt_newer_transports
                                             ex_older = lt_older_transports ).
*     Compare version in QAS with version in prd
*     If a newer version/request is found in prd, then add a warning and
*     continue with the next.
      IF NOT lt_newer_transports[] IS INITIAL.
        LOOP AT lt_newer_transports INTO ls_newer_line.  "#EC CI_NESTED
*         Get transport description:
          SELECT SINGLE as4text FROM  e07t
                                INTO  ls_newer_line-tr_descr
                                WHERE trkorr = ls_newer_line-trkorr
                                AND   langu  = sy-langu. "#EC CI_SEL_NESTED
*         Check if it has been transported to the target system:
          REFRESH: ta_stms_wbo_requests.
          CLEAR:   ta_stms_wbo_requests.
          READ TABLE tms_mgr_buffer INTO tms_mgr_buffer_line
               WITH TABLE KEY request          = ls_newer_line-trkorr
                              target_system    = lp_target.
          IF sy-subrc = 0.
            ta_stms_wbo_requests = tms_mgr_buffer_line-request_infos.
          ELSE.
            CALL FUNCTION 'TMS_MGR_READ_TRANSPORT_REQUEST'
              EXPORTING
                iv_request                 = ls_newer_line-trkorr
                iv_target_system           = lp_target
                iv_header_only             = 'X'
                iv_monitor                 = ' '
              IMPORTING
                et_request_infos           = ta_stms_wbo_requests
              EXCEPTIONS
                read_config_failed         = 1
                table_of_requests_is_empty = 2
                system_not_available       = 3
                OTHERS                     = 4.
            IF sy-subrc <> 0.
              MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
                      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
            ELSE.
              tms_mgr_buffer_line-request       = ls_newer_line-trkorr.
              tms_mgr_buffer_line-target_system = lp_target.
              tms_mgr_buffer_line-request_infos = ta_stms_wbo_requests.
              INSERT tms_mgr_buffer_line INTO TABLE tms_mgr_buffer.
            ENDIF.
          ENDIF.
          READ TABLE ta_stms_wbo_requests INDEX 1
                             INTO st_stms_wbo_requests.
          IF st_stms_wbo_requests-e070 IS NOT INITIAL.
*           Only display the warning if the preceding transport is not
*           one of the selected transports (and in an earlier
*           position)
            me->check_if_same_object( EXPORTING im_line        = ls_main
                                                im_newer_older = ls_newer_line
                                      IMPORTING ex_tabkey      = tp_tabkey
                                                ex_return      = lp_return ).
            CHECK lp_return = abap_true.
*           Fill conflict list
            MOVE-CORRESPONDING ls_newer_line TO me->conflict_line.
            me->conflict_line-warning_lvl  = co_error.
            me->conflict_line-warning_rank = co_error_rank.
            me->conflict_line-warning_txt  = lp_error_text.
            me->conflict_line-objkey       = tp_tabkey.
*           Get the last date the object was imported
            me->get_import_datetime_qas( EXPORTING im_trkorr  = ls_older_line-trkorr
                                         IMPORTING ex_as4time = me->conflict_line-as4time
                                                   ex_as4date = me->conflict_line-as4date ).
*           Check if the transport is in the list
*           Display the warning if the preceding transport is not
*           in the main list. If it is, then display the hint icon.
            READ TABLE ch_main_list
                 INTO  ls_line_temp
                 WITH KEY trkorr = ls_newer_line-trkorr
                 TRANSPORTING prd.
            IF sy-subrc = 0.
              IF ls_line_temp-prd = co_scrap.
*               This newer version is in the list and made visible:
                me->conflict_line-warning_lvl = co_scrap.
              ENDIF.
            ELSE.
              APPEND: me->conflict_line TO me->conflicts.
              CLEAR:  me->conflict_line.
            ENDIF.
          ELSE.
            me->check_if_in_list( EXPORTING im_line  = ls_newer_line
                                            im_tabix = lp_tabix
                                  IMPORTING ex_line  = me->line_found_in_list ).
            IF me->line_found_in_list IS NOT INITIAL.
*             Even if the transport is only in QAS and not in prd (so a
*             newer transport exists, but will not be overwritten), we still
*             want to let the user now about it. To prevent that a newer
*             development exists and should go to production, but it might
*             be forgotten if not selected....
              ls_newer_line-warning_lvl  = ls_main-warning_lvl  = co_hint.
              ls_newer_line-warning_rank = ls_main-warning_rank = co_hint2_rank.
              ls_newer_line-warning_txt  = ls_main-warning_txt  = lp_hint2_text.
*             No need to check further. A newer transport was found but because
*             that newer transport is in the list, we can stop checking for newer
*             transports because that will be done for the transport that is in
*             the list.
              lp_exit = abap_true.
            ELSE.
*             The transport is not yet transported, but if it is found
*             further down in the list, it is okay. Change the warning level
*             from ERROR to INFO.
              ls_newer_line-warning_lvl  = ls_main-warning_lvl  = co_info.
              ls_newer_line-warning_rank = ls_main-warning_rank = co_info_rank.
              ls_newer_line-warning_txt  = ls_main-warning_txt  = lp_info_text.
            ENDIF.
            MOVE-CORRESPONDING ls_newer_line TO me->conflict_line.
            APPEND: me->conflict_line TO me->conflicts.
            CLEAR:  me->conflict_line.
            IF lp_exit = abap_true.
              EXIT.
            ENDIF.
          ENDIF.
        ENDLOOP.
      ENDIF.
*     Select all the transports that are older. These will be checked to
*     see if they have been moved to prd. If the older version has been
*     transported, it is okay.
*     If not, then add a warning and continue with the next record.
      IF NOT lt_older_transports[] IS INITIAL.
        LOOP AT lt_older_transports INTO ls_older_line.  "#EC CI_NESTED
*         Get transport description:
          SELECT SINGLE as4text FROM  e07t
                                INTO  ls_older_line-tr_descr
                                WHERE trkorr = ls_older_line-trkorr
                                AND   langu  = sy-langu. "#EC CI_SEL_NESTED
*         Check if it has been transported to QAS
          REFRESH: ta_stms_wbo_requests.
          CLEAR:   ta_stms_wbo_requests.
          READ TABLE tms_mgr_buffer INTO tms_mgr_buffer_line
                          WITH TABLE KEY request          = ls_older_line-trkorr
                                         target_system    = lp_target.
          IF sy-subrc = 0.
            ta_stms_wbo_requests = tms_mgr_buffer_line-request_infos.
          ELSE.
            CALL FUNCTION 'TMS_MGR_READ_TRANSPORT_REQUEST'
              EXPORTING
                iv_request                 = ls_older_line-trkorr
                iv_target_system           = lp_target
                iv_header_only             = 'X'
                iv_monitor                 = ' '
              IMPORTING
                et_request_infos           = ta_stms_wbo_requests
              EXCEPTIONS
                read_config_failed         = 1
                table_of_requests_is_empty = 2
                system_not_available       = 3
                OTHERS                     = 4.
            IF sy-subrc <> 0.
              MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
                      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
            ELSE.
              tms_mgr_buffer_line-request       = ls_older_line-trkorr.
              tms_mgr_buffer_line-target_system = lp_target.
              tms_mgr_buffer_line-request_infos = ta_stms_wbo_requests.
              INSERT tms_mgr_buffer_line INTO TABLE tms_mgr_buffer.
            ENDIF.
          ENDIF.
*         Was an older transport found that has not yet gone to EEP?
          READ TABLE ta_stms_wbo_requests INDEX 1
                                          INTO st_stms_wbo_requests.
          IF st_stms_wbo_requests-e070 IS INITIAL.
            me->check_if_same_object( EXPORTING im_line        = ls_main
                                                im_newer_older = ls_older_line
                                      IMPORTING ex_tabkey      = tp_tabkey
                                                ex_return      = lp_return ).
            IF lp_return = abap_true.                      "Yes, same object!
              MOVE-CORRESPONDING ls_older_line TO me->conflict_line.
*             Get the last date the object was imported
              me->get_import_datetime_qas( EXPORTING im_trkorr  = ls_older_line-trkorr
                                           IMPORTING ex_as4time = me->conflict_line-as4time
                                                     ex_as4date = me->conflict_line-as4date ).
              me->conflict_line-warning_lvl  = co_warn.
              me->conflict_line-warning_rank = co_warn_rank.
              me->main_list_line-warning_txt = lp_warn_text.
              me->conflict_line-objkey       = tp_tabkey.
*             Check if the transport is in the list
*             Display the warning if the preceding transport is not
*             in the main list. If it is, then display the hint icon.
              READ TABLE ch_main_list
                   WITH KEY trkorr = ls_older_line-trkorr
                   TRANSPORTING NO FIELDS.
              IF sy-subrc = 0.
*               There is a warning but the conflicting transport is
*               ALSO in the list. Display the HINT Icon. The other
*               transport will be checked too, sooner or later...
                me->conflict_line-warning_lvl  = co_hint.
                me->conflict_line-warning_rank = co_hint2_rank.
                me->conflict_line-warning_txt  = lp_hint2_text.
              ENDIF.
*             Check if transport has been released.
*             D - Modifiable
*             L - Modifiable, protected
*             A - Modifiable, protected
*             O - Release started
*             R - Released
*             N - Released (with import protection for repaired objects)
              REFRESH: ta_stms_wbo_requests.
              CLEAR:   ta_stms_wbo_requests.
              READ TABLE tms_mgr_buffer INTO tms_mgr_buffer_line
                              WITH TABLE KEY request          = ls_older_line-trkorr
                                             target_system    = me->dev_system.
              IF sy-subrc = 0.
                ta_stms_wbo_requests = tms_mgr_buffer_line-request_infos.
              ELSE.
                CALL FUNCTION 'TMS_MGR_READ_TRANSPORT_REQUEST'
                  EXPORTING
                    iv_request                 = ls_older_line-trkorr
                    iv_target_system           = me->dev_system
                    iv_header_only             = 'X'
                    iv_monitor                 = ' '
                  IMPORTING
                    et_request_infos           = ta_stms_wbo_requests
                  EXCEPTIONS
                    read_config_failed         = 1
                    table_of_requests_is_empty = 2
                    system_not_available       = 3
                    OTHERS                     = 4.
                IF sy-subrc <> 0.
                  MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
                          WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
                ELSE.
                  tms_mgr_buffer_line-request       = ls_older_line-trkorr.
                  tms_mgr_buffer_line-target_system = lp_target.
                  tms_mgr_buffer_line-request_infos = ta_stms_wbo_requests.
                  INSERT tms_mgr_buffer_line INTO TABLE tms_mgr_buffer.
                ENDIF.
              ENDIF.
              READ TABLE ta_stms_wbo_requests INDEX 1
                                              INTO st_stms_wbo_requests.
              IF st_stms_wbo_requests-e070-trstatus NA 'NR'.
                me->conflict_line-warning_lvl  = co_alert.
                me->conflict_line-warning_rank = co_alert1_rank.
                me->conflict_line-warning_txt  = lp_alert1_text.
              ELSEIF st_stms_wbo_requests-e070-trstatus = 'O'.
                me->conflict_line-warning_lvl  = co_alert.
                me->conflict_line-warning_rank = co_alert2_rank.
                me->conflict_line-warning_txt  = lp_alert2_text.
              ENDIF.
              APPEND: me->conflict_line TO me->conflicts.
              CLEAR:  me->conflict_line.
            ENDIF.
          ELSE.
*           When the first earlier transported version is found,
*           the check must be ended.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.
*     Determine highest warning level in conflict list
*     Only when NOT building the conflict popup
      IF me->building_conflict_popup = abap_false.
        CLEAR: lp_highest_lvl,
               lp_highest_rank,
               lp_highest_text,
               lp_highest_col.
        LOOP AT me->conflicts INTO me->conflict_line.    "#EC CI_NESTED
          IF me->conflict_line-warning_rank > lp_highest_rank.
            lp_highest_lvl  = me->conflict_line-warning_lvl.
            lp_highest_rank = me->conflict_line-warning_rank.
            lp_highest_col  = me->conflict_line-t_color.
            me->determine_warning_text( EXPORTING im_highest_rank = lp_highest_rank
                                        IMPORTING ex_highest_text = lp_highest_text ).
          ENDIF.
        ENDLOOP.
        ls_main-warning_lvl  = lp_highest_lvl.
        ls_main-warning_rank = lp_highest_rank.
        ls_main-warning_txt  = lp_highest_text.
        ls_main-t_color      = lp_highest_col.
        MODIFY: ch_main_list FROM ls_main TRANSPORTING warning_lvl
                                                       warning_rank
                                                       warning_txt
                                                       t_color.
      ENDIF.
*     Refresh the conflict table. But, if the conflict popup is being build
*     for one or more lines, then do NOT refresh the conflict table. Display
*     ALL conflicts for all selected lines.
      IF me->building_conflict_popup = abap_false.
        REFRESH: me->conflicts.
      ENDIF.
    ENDLOOP.

*   Update the conflict table and the main list with DDIC information
    me->do_ddic_check( CHANGING ch_main_list = ch_main_list ).

*   Check if the transport is in Transport Buffer
*   TMS_MGR_REFRESH_IMPORT_QUEUES updates this table
    CLEAR:lp_counter.
    IF me->skip_buffer_chk         = abap_false AND " X = Skip buffer check.
       me->building_conflict_popup = abap_false.    " Never when building popup
      LOOP AT ch_main_list INTO ls_main WHERE prd  <> co_okay
                                        AND   dev  <> co_error
                                        AND   flag =  abap_true.
*       Show the progress indicator
        lp_counter = lp_counter + 1.
        me->progress_indicator( EXPORTING im_counter = lp_counter
                                          im_object  = ls_main-obj_name
                                          im_total   = me->total
                                          im_text    = 'Checking buffer'(050)
                                          im_flag    = ' ' ).
        CLEAR: lp_domnam.
        SELECT SINGLE domnam INTO  lp_domnam FROM tmsbuffer
                             WHERE trkorr EQ ls_main-trkorr
                             AND   sysnam EQ me->prd_system. "#EC CI_SEL_NESTED
        IF sy-subrc EQ 4.
*          ls_main-checked = co_okay.
          ls_main-warning_lvl  = co_alert.
          ls_main-warning_rank = co_alert3_rank.
          ls_main-warning_txt  = lp_alert3_text.
          MODIFY ch_main_list FROM  ls_main.
        ENDIF.
      ENDLOOP.
    ENDIF.
*   Sort ta_conflicts by date time stamp, descending. Most recent should
*   be displayed first:
    SORT me->conflicts BY as4date DESCENDING
                          as4time DESCENDING
                          trkorr  DESCENDING.
    DELETE ADJACENT DUPLICATES FROM me->conflicts
                               COMPARING trkorr object obj_name.
  ENDMETHOD.                    "check_for_conflicts

  METHOD: build_table_keys_popup.
*   A popup is displayed with all tables found in the main list, that
*   have keys. The user has now the option to include them in the
*   checking procedure. This is the only place where the user has a
*   complete overview of the tables that have been found...
*   Declaration for ALV Columns
    DATA: lr_columns_table       TYPE REF TO cl_salv_columns_table.
    DATA: lr_column_table        TYPE REF TO cl_salv_column_table.
    DATA: lt_t_column_ref        TYPE salv_t_column_ref.
    DATA: ls_reference           TYPE salv_s_ddic_reference.
    DATA: ls_s_column_ref        TYPE salv_s_column_ref.
    DATA: st_colo                TYPE lvc_s_colo.
    DATA: lr_events              TYPE REF TO cl_salv_events_table.
*   Declaration for Global Display Settings
    DATA: lr_display_settings    TYPE REF TO cl_salv_display_settings.
*   Declaration for Table Selection settings
    DATA: lr_selections          TYPE REF TO cl_salv_selections.
    DATA: lp_title               TYPE lvc_title.
    DATA: lp_tp_prefix           TYPE char5.
    DATA: lp_xstart              TYPE i VALUE 26.
    DATA: lp_xend                TYPE i.
    DATA: lp_ystart              TYPE i VALUE 7.
    DATA: lp_yend                TYPE i.
    DATA: lp_cw_tabname          TYPE lvc_outlen.  "Length
    DATA: lp_cw_counter          TYPE lvc_outlen.  "Length
    DATA: lp_cw_ddtext           TYPE lvc_outlen.  "Length
    lp_title = 'Keys can be checked for ' &
               'the following tables'(t02).
*   Only if the option to check for table keys is switched ON and
*   checking is active
    CHECK: me->check_tabkeys = abap_true AND
           me->check_flag    = abap_true.
* Determine the transport prefix (if not done already)
    lp_tp_prefix = me->get_tp_prefix( im_dev = me->dev_system ).
*   Fill the internal table to be displayed in the popup:
    LOOP AT me->main_list INTO  me->main_list_line
                          WHERE objfunc    = 'K'
                          AND   keyobject  IS INITIAL
                          AND   keyobjname IS INITIAL
                          AND   obj_name   IN excluded_objects.
      CLEAR: table_keys_line.
      SELECT ddtext FROM  dd02t
                    UP TO 1 ROWS
                    INTO  table_keys_line-ddtext
                    WHERE ddlanguage = sy-langu
                    AND   tabname    = me->main_list_line-obj_name. "#EC CI_SEL_NESTED
      ENDSELECT.
*     Count the keys...
      SELECT COUNT(*)
              FROM  e071k INTO table_keys_line-counter
              WHERE trkorr     =  me->main_list_line-trkorr
              AND   mastertype =  me->main_list_line-object
              AND   NOT trkorr IN  me->project_trkorrs
              AND   trkorr LIKE lp_tp_prefix
              AND   objname    IN excluded_objects.  "#EC CI_SEL_NESTED
      table_keys_line-tabname  = me->main_list_line-obj_name.
      COLLECT table_keys_line INTO table_keys.
    ENDLOOP.
    DELETE table_keys WHERE counter = 0.
    CHECK NOT table_keys[] IS INITIAL.
    SORT  table_keys BY counter DESCENDING.
*   Determine total width
    LOOP AT table_keys INTO table_keys_line.
      me->determine_col_width( EXPORTING im_field    = table_keys_line-tabname
                               CHANGING  ex_colwidth = lp_cw_tabname ).
*      me->determine_col_width( EXPORTING im_field    = table_keys_line-counter
*                               IMPORTING ex_colwidth = lp_cw_counter ).
      me->determine_col_width( EXPORTING im_field    = table_keys_line-ddtext
                               CHANGING  ex_colwidth = lp_cw_ddtext ).
    ENDLOOP.

    lp_xend = lp_cw_tabname + lp_cw_counter + lp_cw_ddtext.

    TRY.
        CALL METHOD cl_salv_table=>factory
          IMPORTING
            r_salv_table = rf_table_keys
          CHANGING
            t_table      = table_keys.
*   Global display settings
        lr_display_settings = rf_table_keys->get_display_settings( ).
*   Activate Striped Pattern
        lr_display_settings->set_striped_pattern( if_salv_c_bool_sap=>true ).
*   Report header
        lr_display_settings->set_list_header( lp_title ).
*       Table Selection Settings
        lr_selections = rf_table_keys->get_selections( ).
        IF lr_selections IS NOT INITIAL.
*         Allow row and column Selection (Adds checkbox)
          lr_selections->set_selection_mode(
                          if_salv_c_selection_mode=>row_column ).
        ENDIF.
*       Get the columns from ALV Table
        lr_columns_table = rf_table_keys->get_columns( ).
        IF lr_columns_table IS NOT INITIAL.
          REFRESH : lt_t_column_ref.
          lt_t_column_ref = lr_columns_table->get( ).
*         Get columns properties
          lr_columns_table->set_optimize( if_salv_c_bool_sap=>true ).
          lr_columns_table->set_key_fixation( if_salv_c_bool_sap=>true ).
*         Individual Column Properties.
          LOOP AT lt_t_column_ref INTO ls_s_column_ref.
            TRY.
                lr_column_table ?=
                  lr_columns_table->get_column( ls_s_column_ref-columnname ).
              CATCH cx_salv_not_found INTO rf_root.
                me->handle_error( EXPORTING rf_oref = rf_root ).
            ENDTRY.
            CASE lr_column_table->get_columnname( ).
              WHEN 'COUNTER'.
                ls_reference-table = 'UGMD_S_STOP_CONDITION'.
                ls_reference-field = 'NUMBER_OF_RESULTS'.
                lr_column_table->set_ddic_reference( ls_reference ).
                lr_column_table->set_alignment( if_salv_c_alignment=>centered ).
            ENDCASE.
          ENDLOOP.
        ENDIF.
*       Register handler for actions
        lr_events = rf_table_keys->get_event( ).
        SET HANDLER lcl_eventhandler_ztct=>on_function_click FOR lr_events.
*       Save reference to access object from handler
        lcl_eventhandler_ztct=>rf_table_keys = rf_table_keys.
*       Use gui-status ST850 from program SAPLKKB
        rf_table_keys->set_screen_status( pfstatus = 'ST850'
                                          report   = 'SAPLKKBL' ).
*       Determine the size of the popup window:
        lp_xend = lp_xend + lp_xstart + 5.
        DESCRIBE TABLE table_keys LINES lp_yend.
        lp_yend = lp_yend + lp_ystart.
*       Display as popup
        rf_table_keys->set_screen_popup( start_column = lp_xstart
                                         end_column   = lp_xend
                                         start_line   = lp_ystart
                                         end_line     = lp_yend ).
        rf_table_keys->display( ).
      CATCH cx_salv_msg INTO rf_root.
        me->handle_error( EXPORTING rf_oref = rf_root ).
    ENDTRY.
  ENDMETHOD.                    "build_table_keys_popup

  METHOD: add_table_keys_to_list .
    DATA: lp_counter          TYPE sy-tabix.
    DATA: lp_total(10)        TYPE n.
    DATA: lt_keys             TYPE tt_request_details.
    DATA: ls_keys             TYPE ty_request_details.
*   Only if the option to check for table keys is switched ON, on the
*   selection screen:
    CHECK: check_tabkeys = abap_true.
*   Check if keys exist in table E071K. Only do this for the records
*   that have not been added already (without key object and name)
*   Remove the entries for which that is the case and add the objects,
*   with the keys.
*   s_exobj contains all tables that we do not want to check.
    LOOP AT table INTO ls_keys WHERE objfunc    = 'K'
                               AND   keyobject  IS INITIAL
                               AND   keyobjname IS INITIAL
                               AND   obj_name   IN excluded_objects.  "Exclude
* Now read the keys from the database
      SELECT object objname tabkey
                FROM e071k
                INNER JOIN e070 ON e070~trkorr EQ e071k~trkorr
                INTO (ls_keys-keyobject,
                      ls_keys-keyobjname,
                      ls_keys-tabkey)
              WHERE   e071k~trkorr     EQ ls_keys-trkorr
                AND   e071k~trkorr     NOT IN me->project_trkorrs
                AND   e071k~trkorr     LIKE me->prefix
                AND   e070~trfunction  NE 'T'
                AND   mastertype =  ls_keys-object
                AND   mastername =  ls_keys-obj_name
                AND   objname    IN excluded_objects. "#EC CI_SEL_NESTED
        APPEND ls_keys TO lt_keys.
      ENDSELECT.
    ENDLOOP.
    SORT lt_keys.
    DELETE ADJACENT DUPLICATES FROM lt_keys.
*   Add the entries for the table keys, and remove the root objects.
    CLEAR: lp_counter.
    DESCRIBE TABLE lt_keys LINES lp_total.
    LOOP AT lt_keys INTO ls_keys.
**     Show the progress indicator
*      lp_counter = lp_counter + 1.
*      me->progress_indicator( EXPORTING im_counter = lp_counter
*                                        im_object  = ls_keys-obj_name
*                                        im_total   = lp_total
*                                        im_text    = 'Determining table keys'(006)
*                                        im_flag    = ' ' ).
      DELETE table WHERE objfunc  = 'K'
                   AND   trkorr   = ls_keys-trkorr
                   AND   object   = ls_keys-object
                   AND   obj_name = ls_keys-obj_name.
    ENDLOOP.
    APPEND LINES OF lt_keys TO table.

  ENDMETHOD.                    "add_table_keys_to_list

  METHOD progress_indicator.
    DATA: lp_gprogtext         TYPE char1024.
    DATA: lp_gprogperc(4)      TYPE p DECIMALS 0.
    DATA: lp_gproggui          TYPE i.
    DATA: lp_step              TYPE i VALUE 1.
    DATA: lp_difference        TYPE i.
    DATA: lp_string            TYPE string.
    DATA: lp_total             TYPE numc10.
    DATA: lp_counter_reset     TYPE i.
*   IM_TOTAL cannot be changed, and we need to remove the leading
*   zero's. That is why intermediate parameter lp_TOTAL was added
    lp_total = im_total.
    lp_difference = lp_total - im_counter.
*   Determine step size
    IF im_flag = abap_true.
      IF lp_difference < 100.
        lp_step = 1.
      ELSEIF lp_difference < 1000.
        lp_step = 50.
      ELSE.
        lp_step = 100.
      ENDIF.
    ENDIF.
*   Number of selected items on GUI:
    CHECK lp_step <> 0.
    lp_gproggui = im_counter MOD lp_step.
    IF lp_gproggui = 0.
      WRITE im_counter TO lp_gprogtext LEFT-JUSTIFIED.
      IF lp_total <> 0.
        SHIFT lp_total LEFT DELETING LEADING '0'.
        CONCATENATE lp_gprogtext 'of' lp_total
                    INTO lp_gprogtext SEPARATED BY ' '.
      ENDIF.
      IF im_object IS NOT INITIAL.
        CONCATENATE '(' im_object ')'
                    INTO lp_string.
        CONDENSE lp_string.
      ENDIF.
      CONCATENATE lp_gprogtext im_text lp_string
                  INTO lp_gprogtext
                  SEPARATED BY ' '.
      CONDENSE lp_gprogtext.
      CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
        EXPORTING
          percentage = lp_gprogperc
          text       = lp_gprogtext.
    ENDIF.

* To avoid timeouts
    IF me->check_tabkeys = abap_true.
      lp_counter_reset = im_counter MOD 5.
    ELSE.
      lp_counter_reset = im_counter MOD 50.
    ENDIF.

    IF lp_counter_reset = 0.
      CALL FUNCTION 'TH_REDISPATCH'.
    ENDIF.

  ENDMETHOD.                    "progress_indicator

  METHOD get_main_transports.
    DATA: ta_main_list_vrsd  TYPE tt_request_details.
    DATA: st_main_list_vrsd  TYPE ty_request_details.
    DATA: lp_return          TYPE c.
    FIELD-SYMBOLS: <l_main_list> TYPE ty_request_details.
    REFRESH: ta_main_list_vrsd.
    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        text = 'Selecting data...'(014).
*   Join over E070, E071:
*   Description is read later to prevent complicated join and
*   increased runtime
    SELECT a~trkorr   a~trfunction a~trstatus
           a~as4user  a~as4date    a~as4time
           b~pgmid b~object   b~obj_name   b~objfunc
           INTO CORRESPONDING FIELDS OF TABLE me->main_list
           FROM  e070 AS a JOIN e071 AS b
             ON  a~trkorr  = b~trkorr
           WHERE a~trkorr  IN im_trkorr_range
           AND   strkorr   = ''
           AND   a~trkorr  LIKE me->prefix
           AND ( pgmid     = 'LIMU' OR
                 pgmid     = 'R3TR' ).

    IF me->main_list[] IS NOT INITIAL.
      LOOP AT me->main_list ASSIGNING <l_main_list>.
*       If the transports should be checked, flag it.
        <l_main_list>-flag = abap_true.
*       Read transport description:
        SELECT SINGLE  as4text
                 FROM  e07t
                 INTO <l_main_list>-tr_descr
                 WHERE trkorr = <l_main_list>-trkorr
                 AND   langu  = sy-langu.            "#EC CI_SEL_NESTED
      ENDLOOP.
    ENDIF.
    SORT me->main_list.
    DELETE ADJACENT DUPLICATES FROM me->main_list.
*   Only continue if there are transports to check...
    CHECK NOT me->main_list[] IS INITIAL.
*   Check if project is in selection range:
    IF project_range IS NOT INITIAL.
      LOOP AT me->main_list ASSIGNING <l_main_list>.
        SELECT SINGLE reference
               FROM e070a
               INTO  <l_main_list>-project
               WHERE trkorr = <l_main_list>-trkorr
               AND   attribute = 'SAP_CTS_PROJECT'   "#EC CI_SEL_NESTED
               AND   reference IN project_range.
        IF sy-subrc <> 0.
          DELETE me->main_list INDEX sy-tabix.
        ENDIF.
      ENDLOOP.
    ENDIF.
*   Check if the searchstring is in the transport description:
    IF NOT me->search_string IS INITIAL.
      LOOP AT me->main_list INTO me->main_list_line.
        IF me->search_string CS '*'.
          IF me->main_list_line-tr_descr NP me->search_string.
            DELETE me->main_list INDEX sy-tabix.
            CONTINUE.
          ENDIF.
        ELSE.
          IF me->main_list_line-tr_descr NS me->search_string.
            DELETE me->main_list INDEX sy-tabix.
            CONTINUE.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.
    CHECK me->main_list[] IS NOT INITIAL.
*   Also read from the version table VRSD. This table contains all
*   dependent objects. For example: If from E071 a function group
*   is retrieved, VRSD will contain all functions too.
    SELECT korrnum objtype objname
           author  datum zeit
           FROM  vrsd
           INTO (st_main_list_vrsd-trkorr,
                 st_main_list_vrsd-object,
                 st_main_list_vrsd-obj_name,
                 st_main_list_vrsd-as4user,
                 st_main_list_vrsd-as4date,
                 st_main_list_vrsd-as4time)
           FOR ALL ENTRIES IN me->main_list
           WHERE korrnum   =  me->main_list-trkorr.
      READ TABLE me->main_list INTO me->main_list_line
                               WITH KEY trkorr = st_main_list_vrsd-trkorr.
      MOVE: st_main_list_vrsd-object   TO me->main_list_line-object,
            st_main_list_vrsd-obj_name TO me->main_list_line-obj_name,
            st_main_list_vrsd-as4user  TO me->main_list_line-as4user,
            st_main_list_vrsd-as4date  TO me->main_list_line-as4date,
            st_main_list_vrsd-as4time  TO me->main_list_line-as4time.
*     Only append if the object from VRSD does not already exist in the
*     main list:
      READ TABLE me->main_list WITH KEY trkorr  = me->main_list_line-trkorr
                                        object   = me->main_list_line-object
                                        obj_name = me->main_list_line-obj_name
                                        TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        me->main_list_line-flag = abap_true.
        APPEND me->main_list_line TO ta_main_list_vrsd.
      ENDIF.
    ENDSELECT.
*   Duplicates may exist if the same object exists in different tasks
*   belonging to the same request:
    SORT ta_main_list_vrsd DESCENDING.
    DELETE ADJACENT DUPLICATES FROM ta_main_list_vrsd
                    COMPARING trkorr object obj_name.
*   Now add all VRSD entries to the main list:
    APPEND LINES OF ta_main_list_vrsd TO me->main_list.
    me->sort_main_list( ).
  ENDMETHOD.                    "get_main_transports

  METHOD get_tp_info.
*   Join over E070, E071:
*   Description is read later to prevent complicated join and
*   increased runtime
    SELECT SINGLE a~trkorr  a~trfunction a~trstatus
                  a~as4user a~as4date  a~as4time
                  b~object  b~obj_name
           INTO (re_line-trkorr,
                 re_line-trfunction,
                 re_line-trstatus,
                 re_line-as4user,
                 re_line-as4date,
                 re_line-as4time,
                 re_line-object,
                 re_line-obj_name)
           FROM  e070 AS a JOIN e071 AS b
           ON    a~trkorr   = b~trkorr
           WHERE a~trkorr   = im_trkorr
           AND   strkorr    = ''
           AND   b~obj_name = im_obj_name.
*   Read transport description:
    SELECT SINGLE  as4text
             FROM  e07t
             INTO  re_line-tr_descr
             WHERE trkorr = im_trkorr
             AND   langu  = sy-langu.
    re_line-checked_by = sy-uname.
*       First get the descriptions (Status/Type/Project):
*       Retrieve texts for Status Description
    SELECT ddtext
           FROM  dd07t
           INTO  re_line-status_text UP TO 1 ROWS
           WHERE domname    = 'TRSTATUS'
           AND   ddlanguage = sy-langu
           AND   domvalue_l = re_line-trstatus.      "#EC CI_SEL_NESTED
    ENDSELECT.
*       Retrieve texts for Description of request/task type
    SELECT ddtext
           FROM  dd07t
           INTO  re_line-trfunction_txt UP TO 1 ROWS
           WHERE domname    = 'TRFUNCTION'
           AND   ddlanguage = sy-langu
           AND   domvalue_l = re_line-trfunction.    "#EC CI_SEL_NESTED
    ENDSELECT.
*       Retrieve the project number (and description):
    SELECT reference
           FROM  e070a UP TO 1 ROWS
           INTO  re_line-project
           WHERE trkorr    = re_line-trkorr
           AND   attribute = 'SAP_CTS_PROJECT'.      "#EC CI_SEL_NESTED
      SELECT descriptn
             FROM  ctsproject UP TO 1 ROWS
             INTO  re_line-project_descr              "#EC CI_SGLSELECT
             WHERE trkorr  = re_line-project.        "#EC CI_SEL_NESTED
      ENDSELECT.
    ENDSELECT.
*       Retrieve the description of the status
    SELECT ddtext
           FROM  dd07t UP TO 1 ROWS
           INTO  re_line-trstatus
           WHERE domname    = 'TRSTATUS'
           AND   ddlanguage = sy-langu
           AND   domvalue_l = re_line-trstatus.      "#EC CI_SEL_NESTED
    ENDSELECT.

  ENDMETHOD.                    "get_tp_info

  METHOD get_added_objects.
    DATA: lp_tabix               TYPE sytabix,
          ls_main                TYPE ty_request_details,
          ls_main_list_vrsd      TYPE ty_request_details,
          lt_main_list_vrsd      TYPE tt_request_details,
          ls_added               TYPE ty_request_details.
    FIELD-SYMBOLS: <l_main_list> TYPE ty_request_details.
    REFRESH: ex_to_add.
    REFRESH: lt_main_list_vrsd.
    CLEAR:   ls_main.
*   Select all requests (not tasks) in the range. Objects belonging to
*   the request are included in the table.
    SELECT a~trkorr   a~trfunction a~trstatus
           a~as4user  a~as4date    a~as4time
           b~object   b~obj_name   b~objfunc
           INTO CORRESPONDING FIELDS OF TABLE ex_to_add
           FROM  e070 AS a JOIN e071 AS b
             ON  a~trkorr = b~trkorr
           WHERE a~trkorr IN im_to_add
           AND   a~strkorr = ''
           AND   ( b~pgmid = 'LIMU' OR
                   b~pgmid = 'R3TR' OR
                   b~pgmid = 'R3OB' OR
                   b~pgmid = 'LANG').
*   Read transport description:
    IF ex_to_add[] IS NOT INITIAL.
      LOOP AT ex_to_add ASSIGNING <l_main_list>.
        <l_main_list>-flag = abap_true.
        SELECT SINGLE  as4text
                 FROM  e07t
                 INTO <l_main_list>-tr_descr
                 WHERE trkorr = <l_main_list>-trkorr
                 AND   langu  = sy-langu.            "#EC CI_SEL_NESTED
      ENDLOOP.
    ENDIF.
*   Also read from the version table VRSD. This table contains all
*   dependent objects. For example: If from E071 a function group
*   is retrieved, VRSD will contain all functions too.
    IF NOT ex_to_add[] IS INITIAL.
      SELECT korrnum objtype objname
             author  datum zeit
             FROM  vrsd
             INTO (ls_main_list_vrsd-trkorr,
                   ls_main_list_vrsd-object,
                   ls_main_list_vrsd-obj_name,
                   ls_main_list_vrsd-as4user,
                   ls_main_list_vrsd-as4date,
                   ls_main_list_vrsd-as4time)
             FOR ALL ENTRIES IN ex_to_add
             WHERE korrnum   =  ex_to_add-trkorr.
        READ TABLE ex_to_add
                   INTO ls_main
                   WITH KEY trkorr = ls_main_list_vrsd-trkorr.
        MOVE: ls_main_list_vrsd-object   TO ls_main-object,
              ls_main_list_vrsd-obj_name TO ls_main-obj_name,
              ls_main_list_vrsd-as4user  TO ls_main-as4user,
              ls_main_list_vrsd-as4date  TO ls_main-as4date,
              ls_main_list_vrsd-as4time  TO ls_main-as4time.
*       Only append if the object from VRSD does not already exist
*       in the main list:
        READ TABLE ex_to_add WITH KEY trkorr   = ls_main-trkorr
                                      object   = ls_main-object
                                      obj_name = ls_main-obj_name
                             TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          ls_main-flag = abap_true.
          APPEND ls_main TO lt_main_list_vrsd.
        ENDIF.
      ENDSELECT.
    ENDIF.
*   Now add all VRSD entries to the main list:
    APPEND LINES OF lt_main_list_vrsd TO ex_to_add.
    me->add_table_keys_to_list( IMPORTING table = ex_to_add ).
*   Only add the records that are not existing in the main list, so we
*   do not add the records that already exist in the main list.
    LOOP AT ex_to_add INTO ls_added.
      lp_tabix = sy-tabix.
      READ TABLE me->main_list WITH KEY trkorr     = ls_added-trkorr
                                        object     = ls_added-object
                                        obj_name   = ls_added-obj_name
                                        keyobject  = ls_added-keyobject
                                        keyobjname = ls_added-keyobjname
                                        tabkey     = ls_added-tabkey
                               TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
*       If the added transports are already in the list, but in prd, they
*       will be 'invisible', because the records with prd icon = co_okay
*       are filtered out. So, the prd icon needs to be changed to co_scrap
*       to become visible. We just make sure that all records for this
*       transport are made visible.
        LOOP AT me->main_list INTO  me->main_list_line   "#EC CI_NESTED
                              WHERE trkorr     = ls_added-trkorr
                              AND   object     = ls_added-object
                              AND   obj_name   = ls_added-obj_name
                              AND   keyobject  = ls_added-keyobject
                              AND   keyobjname = ls_added-keyobjname
                              AND   tabkey     = ls_added-tabkey
                              AND   prd        = co_okay.
          me->main_list_line-prd = co_scrap.
          MODIFY me->main_list FROM me->main_list_line INDEX sy-tabix.
        ENDLOOP.
*       No need to add this transport again:
        DELETE ex_to_add INDEX lp_tabix.
      ENDIF.
    ENDLOOP.
    SORT: ex_to_add.
    DELETE ADJACENT DUPLICATES FROM ex_to_add.
  ENDMETHOD.                    "get_added_objects

  METHOD get_additional_tp_info.
    DATA: lt_tr_cofilines      TYPE tr_cofilines.
    DATA: ls_tstrfcofil        TYPE tstrfcofil.
    DATA: ta_stms_wbo_requests TYPE TABLE OF stms_wbo_request.
    DATA: lp_retcode           TYPE strw_int4.
    DATA: st_stms_wbo_requests TYPE stms_wbo_request.
    DATA: st_systems           TYPE ctslg_system.
    DATA: lp_counter           TYPE i.
    DATA: lp_index             TYPE sytabix.
    DATA: lp_indexinc          TYPE sytabix.
    DATA: lp_trkorr            TYPE trkorr.
    DATA: ls_main_backup       TYPE ty_request_details.
    CLEAR: lp_counter,
           me->total.
*   The CHECKED_BY field is always going to be filled. If it is empty,
*   then this subroutine has not yet been executed for the record, and has
*   to be executed. Additional info ONLY needs to be gathered once.
*   This needs to be checked because transports can be added. If that
*   happened, additional info only needs to be retrieved for the added
*   transports.
    LOOP AT ch_table INTO me->main_list_line
                     WHERE flag = abap_true.
      me->total = me->total + 1.
    ENDLOOP.
    LOOP AT ch_table INTO me->main_list_line
                     WHERE flag = abap_true.
*     Show the progress indicator
      IF me->main_list_line-prd <> co_okay.
        lp_counter = lp_counter + 1.
        me->progress_indicator( EXPORTING im_counter = lp_counter
                                          im_object  = me->main_list_line-obj_name
                                          im_total   = me->total
                                          im_text    = 'Object data retrieved...'(010)
                                          im_flag    = abap_true ).
      ENDIF.
      lp_index    = sy-tabix.
      lp_indexinc = lp_index + 1. " To check next lines for same object
*     Only need to retrieve the additional info once, when a new transport
*     is encountered. This info is then copied to all the records (each
*     object) for the same request. So, only if the transport number is
*     different from the previous one.
      IF lp_trkorr <> me->main_list_line-trkorr.
        lp_trkorr = me->main_list_line-trkorr.
        me->main_list_line-checked_by = sy-uname.
*       First get the descriptions (Status/Type/Project):
*       Retrieve texts for Status Description
        SELECT ddtext
               FROM  dd07t
               INTO  me->main_list_line-status_text UP TO 1 ROWS
               WHERE domname    = 'TRSTATUS'
               AND   ddlanguage = sy-langu
               AND   domvalue_l = me->main_list_line-trstatus. "#EC CI_SEL_NESTED
        ENDSELECT.
*       Retrieve texts for Description of request/task type
        SELECT ddtext
               FROM  dd07t
               INTO  me->main_list_line-trfunction_txt UP TO 1 ROWS
               WHERE domname    = 'TRFUNCTION'
               AND   ddlanguage = sy-langu
               AND   domvalue_l = me->main_list_line-trfunction. "#EC CI_SEL_NESTED
        ENDSELECT.
*       Retrieve the project number (and description):
        SELECT reference
               FROM  e070a UP TO 1 ROWS
               INTO  me->main_list_line-project
               WHERE trkorr    = me->main_list_line-trkorr
               AND   attribute = 'SAP_CTS_PROJECT'.  "#EC CI_SEL_NESTED
          SELECT descriptn
                 FROM  ctsproject UP TO 1 ROWS
                 INTO  me->main_list_line-project_descr "#EC CI_SGLSELECT
                 WHERE trkorr  = me->main_list_line-project. "#EC CI_SEL_NESTED
          ENDSELECT.
        ENDSELECT.
*       Retrieve the description of the status
        SELECT ddtext
               FROM  dd07t UP TO 1 ROWS
               INTO  me->main_list_line-trstatus
               WHERE domname    = 'TRSTATUS'
               AND   ddlanguage = sy-langu
               AND   domvalue_l = me->main_list_line-trstatus. "#EC CI_SEL_NESTED
        ENDSELECT.
*       Check if transport has been released.
*       D - Modifiable
*       L - Modifiable, protected
*       A - Modifiable, protected
*       O - Release started
*       R - Released
*       N - Released (with import protection for repaired objects)
        REFRESH: ta_stms_wbo_requests.
        CLEAR:   ta_stms_wbo_requests.
        READ TABLE tms_mgr_buffer INTO tms_mgr_buffer_line
                        WITH TABLE KEY request          = me->main_list_line-trkorr
                                       target_system    = me->dev_system.
        IF sy-subrc = 0.
          ta_stms_wbo_requests = tms_mgr_buffer_line-request_infos.
        ELSE.
          CALL FUNCTION 'TMS_MGR_READ_TRANSPORT_REQUEST'
            EXPORTING
              iv_request                 = me->main_list_line-trkorr
              iv_target_system           = me->dev_system
              iv_header_only             = 'X'
              iv_monitor                 = ' '
            IMPORTING
              et_request_infos           = ta_stms_wbo_requests
            EXCEPTIONS
              read_config_failed         = 1
              table_of_requests_is_empty = 2
              system_not_available       = 3
              OTHERS                     = 4.
          IF sy-subrc <> 0.
            MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
                    WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
          ELSE.
            tms_mgr_buffer_line-request       = me->main_list_line-trkorr.
            tms_mgr_buffer_line-target_system = me->dev_system.
            tms_mgr_buffer_line-request_infos = ta_stms_wbo_requests.
            INSERT tms_mgr_buffer_line INTO TABLE tms_mgr_buffer.
          ENDIF.
        ENDIF.
        READ TABLE ta_stms_wbo_requests INDEX 1
                                        INTO st_stms_wbo_requests.
*       Check if there is documentation available
        CLEAR: me->main_list_line-info.
        IF NOT st_stms_wbo_requests-docu[] IS INITIAL.
          me->check_documentation( EXPORTING im_trkorr = me->main_list_line-trkorr
                                   CHANGING  ch_table  = ch_table ).
        ENDIF.
* Check the returncode of this transport to QAS
        CALL FUNCTION 'STRF_READ_COFILE'
          EXPORTING
            iv_trkorr     = me->main_list_line-trkorr
          TABLES
            tt_cofi_lines = lt_tr_cofilines
          EXCEPTIONS
            wrong_call    = 0
            no_info_found = 0
            OTHERS        = 0.
        READ TABLE lt_tr_cofilines INTO ls_tstrfcofil
                                   WITH KEY tarsystem = qas_system
                                            function  = 'G'.
        me->main_list_line-retcode = ls_tstrfcofil-retcode.
        IF st_stms_wbo_requests-e070-trstatus NA 'NR'.
          me->main_list_line-warning_lvl  = co_alert.
          me->main_list_line-warning_rank = co_alert1_rank.
          me->main_list_line-warning_txt  = lp_alert1_text.
        ELSEIF st_stms_wbo_requests-e070-trstatus = 'O'.
          me->main_list_line-warning_lvl  = co_alert.
          me->main_list_line-warning_rank = co_alert2_rank.
          me->main_list_line-warning_txt  = lp_alert2_text.
        ELSE.
*         Retrieve the environments where the transport can be found.
*         Read the info of the request (transport log) to determine the
*         highest environment the transport has been moved to.
          CALL FUNCTION 'TR_READ_GLOBAL_INFO_OF_REQUEST'
            EXPORTING
              iv_trkorr = me->main_list_line-trkorr
            IMPORTING
              es_cofile = st_request-cofile.

          IF st_request-cofile-systems IS INITIAL.
*           Transport log does not exist: not released or log deleted
            me->main_list_line-warning_lvl  = co_alert.
            me->main_list_line-warning_rank = co_alert0_rank.
            me->main_list_line-warning_txt  = lp_alert0_text.
*           First check if the object can also be found further down in
*           the list. If it is, then THAT transport will be checked.
*           Because, even if this transport's log can't be read, if the
*           same object is found later in the list, that one will be
*           checked too. We don't have to worry about the fact that the
*           log does not exist for this transport.
            LOOP AT ch_table INTO  me->line_found_in_list FROM lp_indexinc
                             WHERE object     =  me->main_list_line-object
                             AND   obj_name   =  me->main_list_line-obj_name
                             AND   keyobject  =  me->main_list_line-keyobject
                             AND   keyobjname =  me->main_list_line-keyobjname
                             AND   tabkey     =  me->main_list_line-tabkey
                             AND   prd        <> co_okay. "#EC CI_NESTED
              EXIT.
            ENDLOOP.
            IF sy-subrc = 0.
              me->main_list_line-warning_lvl  = co_hint.
              me->main_list_line-warning_rank = co_hint3_rank.
              me->main_list_line-warning_txt  = lp_hint3_text.
            ENDIF.
          ELSE.
*           Initialize environment fields. The environments will be
*           checked
*           and updated with the correct environment later
            me->main_list_line-dev = co_inact.
            me->main_list_line-qas = co_inact.
            me->main_list_line-prd = co_inact.
*           Now check in which environments the transport can be found
            LOOP AT st_request-cofile-systems INTO st_systems. "#EC CI_NESTED
*             For each environment, set the status icon:
              CASE st_systems-systemid.
                WHEN me->dev_system.
                  me->main_list_line-dev = co_okay. "Green - Exists
                WHEN me->qas_system.
                  me->main_list_line-qas = co_okay. "Green - Exists
*                 Get the latest date/time stamp
                  DESCRIBE TABLE st_systems-steps LINES tp_lines.
                  READ TABLE st_systems-steps INTO st_steps
                                              INDEX tp_lines.
                  CHECK st_steps-stepid <> '<'.

                  DESCRIBE TABLE st_steps-actions LINES tp_lines.
                  READ TABLE st_steps-actions INTO st_actions
                                              INDEX tp_lines.
                  MOVE st_actions-time TO me->main_list_line-as4time.
                  MOVE st_actions-date TO me->main_list_line-as4date.
                WHEN me->prd_system.
                  DESCRIBE TABLE st_systems-steps LINES tp_lines.
                  READ TABLE st_systems-steps INTO st_steps
                                              INDEX tp_lines.
                  CHECK st_steps-stepid <> '<'.
                  me->main_list_line-prd = co_okay. "Green - Exists
                WHEN OTHERS.
              ENDCASE.
            ENDLOOP.
          ENDIF.
        ENDIF.
*       Update the main table from the workarea.
        MODIFY ch_table FROM me->main_list_line
                        INDEX lp_index
                        TRANSPORTING checked_by
                                     status_text
                                     trfunction_txt
                                     trstatus
                                     tr_descr
                                     retcode
                                     info
                                     warning_lvl
                                     warning_txt
                                     dev
                                     qas
                                     prd
                                     as4time
                                     as4date
                                     project
                                     project_descr.
*       Keep the workarea for the other objects within the same transport.
*       No need to select the same data for each objetc because it is the
*       same for all the transport objects (data retrieved on transport
*       level).
        ls_main_backup = me->main_list_line.
        CONTINUE.
      ELSE.
*       Update the main table from the workarea.
        MODIFY ch_table FROM ls_main_backup
                        INDEX lp_index
                        TRANSPORTING checked_by
                                     status_text
                                     trfunction_txt
                                     trstatus
                                     tr_descr
                                     retcode
                                     info
                                     warning_lvl
                                     warning_txt
                                     dev
                                     qas
                                     prd
                                     as4time
                                     as4date
                                     project
                                     project_descr.
        CONTINUE.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.                    "get_additional_tp_info

  METHOD add_to_list.
*   Add the records:
    APPEND LINES OF im_to_add TO ex_main.
*   Re-sort the list:
    me->sort_main_list( ).
  ENDMETHOD.                    "add_to_list

  METHOD build_conflict_popup.
    DATA: lr_events          TYPE REF TO cl_salv_events_table.
    DATA: ls_conflict        TYPE ty_request_details.
    DATA: lp_xend            TYPE i.
    DATA: lp_yend            TYPE i.
    DATA: lp_xstart          TYPE i VALUE 50.
    DATA: lp_ystart          TYPE i VALUE 7.
*   Prevent the conflicts popup to be build multiple times
    CHECK rf_conflicts IS INITIAL.
*   Because we are going to only display the popup, the main list
*   does not need to be checked. So we set a flag. This makes sure
*   that all conflicting transports are added to the conflict list
*   and the main list is NOT checked again.
    me->set_building_conflict_popup(  ).
    me->flag_for_process( EXPORTING rows = rows
                                    cell = cell ).
    me->check_for_conflicts( CHANGING ch_main_list = me->main_list ).
*   If the button to add conflicts is clicked (not a double-click), then
*   remove from the popup all low-level warning messages
    IF sy-ucomm = '&ADD'.
      LOOP AT me->conflicts INTO ls_conflict
                            WHERE warning_rank < co_info_rank.
        DELETE me->conflicts INDEX sy-tabix.
      ENDLOOP.
    ENDIF.
*   Check if there are entries in the conflicts. If not, display a
*   message
    IF me->conflicts IS INITIAL.
      MESSAGE i000(db)
         WITH 'No transports need to be added'(019)
              'To see the conflicts, doubleclick the warning'(020).
      EXIT.
    ENDIF.
    TRY.
        CALL METHOD cl_salv_table=>factory
          IMPORTING
            r_salv_table = rf_conflicts
          CHANGING
            t_table      = me->conflicts.
*       Set ALV properties
        me->set_properties_conflicts( EXPORTING im_table = me->conflicts
                                      IMPORTING ex_xend  = lp_xend ).
*       Set Tooltips
        me->alv_set_tooltips( EXPORTING im_table = rf_conflicts ).
*       Register handler for actions
        lr_events = rf_conflicts->get_event( ).
        SET HANDLER lcl_eventhandler_ztct=>on_function_click FOR lr_events.
*       Save reference to access object from handler
        lcl_eventhandler_ztct=>rf_conflicts = rf_conflicts.
*       Use gui-status ST850 from program SAPLKKB
        rf_conflicts->set_screen_status( pfstatus      = 'ST850'
                                         report        = 'SAPLKKBL' ).
*       Determine the size of the popup window:
        lp_xend = lp_xend + lp_xstart + 5.
        DESCRIBE TABLE me->conflicts LINES lp_yend.
        IF lp_yend < 5.
          lp_yend = 5.
        ENDIF.
        lp_yend = lp_yend + lp_ystart + 1.
*       Display as popup
        rf_conflicts->set_screen_popup( start_column = lp_xstart
                                        end_column   = lp_xend
                                        start_line   = lp_ystart
                                        end_line     = lp_yend ).
        rf_conflicts->display( ).
      CATCH cx_salv_msg INTO rf_root.
        me->handle_error( EXPORTING rf_oref = rf_root ).
    ENDTRY.
    FREE rf_conflicts.
    me->set_building_conflict_popup( abap_false ).
  ENDMETHOD.                    "build_conflict_popup

  METHOD delete_tp_from_list.
    DATA: ra_trkorr TYPE RANGE OF trkorr.
    DATA: ls_trkorr LIKE LINE  OF ra_trkorr.
    DATA: ls_row TYPE int4.
*   If row(s) are selected, use the table
* Add transports to range
    ls_trkorr-sign   = 'I'.
    ls_trkorr-option = 'EQ'.
    LOOP AT rows INTO ls_row.
      READ TABLE me->main_list INTO  me->main_list_line
                               INDEX ls_row.
      ls_trkorr-low = me->main_list_line-trkorr.
      APPEND ls_trkorr TO ra_trkorr.
    ENDLOOP.
    SORT ra_trkorr.
    DELETE ADJACENT DUPLICATES FROM ra_trkorr.
    DELETE me->main_list WHERE trkorr IN ra_trkorr.
  ENDMETHOD.                    "delete_tp_from_list

  METHOD flag_same_objects.
    DATA: lt_main_list_copy TYPE tt_request_details.
*   Only relevant if there is a check to be done
    CHECK me->check_flag = abap_true.
*   Set check flag for all transports that are going to be refreshed
*   because all of these need to be checked again.
    lt_main_list_copy[] = ex_main_list[].
    LOOP AT ex_main_list INTO me->main_list_line
                         WHERE flag = abap_true.
*     Also flag all the objects already existing in the main table
*     that are in the added list: They need to be checked again.
      LOOP AT lt_main_list_copy[] INTO  me->main_list_line
                                  WHERE object     = me->main_list_line-object
                                  AND   obj_name   = me->main_list_line-obj_name
                                  AND   keyobject  = me->main_list_line-keyobject
                                  AND   keyobjname = me->main_list_line-keyobjname
                                  AND   tabkey     = me->main_list_line-tabkey
                                  AND   flag = abap_false. "#EC CI_NESTED
        me->main_list_line-flag = abap_true.
        MODIFY lt_main_list_copy FROM  me->main_list_line
                                 INDEX sy-tabix
                                 TRANSPORTING flag.
      ENDLOOP.
    ENDLOOP.
    ex_main_list[] = lt_main_list_copy[].
    FREE lt_main_list_copy.
  ENDMETHOD.                    "flag_same_objects

  METHOD mark_all_tp_records.
    DATA: ra_trkorr TYPE RANGE OF trkorr.
    DATA: ls_trkorr LIKE LINE  OF ra_trkorr.
    DATA: ls_row    TYPE int4.
* Add transports to range
    ls_trkorr-sign   = 'I'.
    ls_trkorr-option = 'EQ'.
* If row(s) are selected, use the table
    LOOP AT im_rows INTO ls_row.
      READ TABLE me->main_list INTO  me->main_list_line
                               INDEX ls_row.
      ls_trkorr-low = me->main_list_line-trkorr.
      APPEND ls_trkorr TO ra_trkorr.
    ENDLOOP.
* If no rows were selected, take the current cell instead
    IF sy-subrc <> 0.
      READ TABLE me->main_list INTO  me->main_list_line
                               INDEX im_cell-row.
      ls_trkorr-low = me->main_list_line-trkorr.
      APPEND ls_trkorr TO ra_trkorr.
    ENDIF.
    CHECK ra_trkorr IS NOT INITIAL.
    SORT ra_trkorr.
    DELETE ADJACENT DUPLICATES FROM ra_trkorr.
* Mark all records for all marked transports
    LOOP AT me->main_list INTO me->main_list_line
                          WHERE trkorr IN ra_trkorr.
      APPEND sy-tabix TO im_rows.
    ENDLOOP.
    SORT im_rows.
    DELETE ADJACENT DUPLICATES FROM im_rows.
  ENDMETHOD.                    "mark_all_tp_records

  METHOD clear_flags.
    LOOP AT me->main_list INTO  me->main_list_line
                          WHERE flag = abap_true.
      CLEAR: me->main_list_line-flag.
      MODIFY me->main_list FROM me->main_list_line
                           TRANSPORTING flag.
    ENDLOOP.
  ENDMETHOD.                    "clear_flags

  METHOD get_filename.
    DATA: lp_window_title TYPE string,
          lp_rc           TYPE i,
          lp_desktop      TYPE string,
          lt_filetable    TYPE filetable.
* Finding desktop
    CALL METHOD cl_gui_frontend_services=>get_desktop_directory
      CHANGING
        desktop_directory    = lp_desktop
      EXCEPTIONS
        cntl_error           = 1
        error_no_gui         = 2
        not_supported_by_gui = 3
        OTHERS               = 4.
    IF sy-subrc <> 0.
      MESSAGE e001(00) WITH
          'Desktop not found'(012).
    ENDIF.
* Update View
    CALL METHOD cl_gui_cfw=>update_view
      EXCEPTIONS
        cntl_system_error = 1
        cntl_error        = 2
        OTHERS            = 3.
    lp_window_title = 'Select a transportlist'(013).
    CALL METHOD cl_gui_frontend_services=>file_open_dialog
      EXPORTING
        window_title            = lp_window_title
        default_extension       = 'TXT'
        default_filename        = 'ZTCT_FILE'
        file_filter             = '.TXT'
        initial_directory       = lp_desktop
      CHANGING
        file_table              = lt_filetable
        rc                      = lp_rc
      EXCEPTIONS
        file_open_dialog_failed = 1
        cntl_error              = 2
        error_no_gui            = 3
        not_supported_by_gui    = 4
        OTHERS                  = 5.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.
    READ TABLE lt_filetable INDEX 1 INTO ex_file.
  ENDMETHOD.                    "get_filename

  METHOD main_to_tab_delimited.
    DATA: lp_string             TYPE string.
    DATA: lp_type               TYPE char01.
    DATA: lp_com                TYPE i.
    FIELD-SYMBOLS: <l_fs>       TYPE ANY.

*   Determine the number of fields in the structure
    DATA: lr_tabledescr         TYPE REF TO cl_abap_tabledescr,
          lr_typedescr          TYPE REF TO cl_abap_typedescr,
          lr_structdescr        TYPE REF TO cl_abap_structdescr,
          lt_abap_component_tab TYPE abap_component_tab,
          ls_abap_component     TYPE abap_componentdescr.

    TRY.
        lr_typedescr = cl_abap_tabledescr=>describe_by_data( p_data = me->main_list ).
        lr_tabledescr ?= lr_typedescr.
        lr_structdescr ?= lr_tabledescr->get_table_line_type( ).
      CATCH cx_sy_move_cast_error INTO rf_root.
        me->handle_error( EXPORTING rf_oref = rf_root ).
      CATCH cx_root INTO rf_root.
        me->handle_error( EXPORTING rf_oref = rf_root ).
    ENDTRY.

* Build header line
    REFRESH: ex_tab_delimited.
    lt_abap_component_tab = lr_structdescr->get_components( ).
    LOOP AT lt_abap_component_tab INTO ls_abap_component.
      CONCATENATE lp_string tp_tab ls_abap_component-name INTO lp_string.
    ENDLOOP.
    SHIFT lp_string LEFT DELETING LEADING tp_tab.
    APPEND lp_string TO ex_tab_delimited.
*   Now modify the lines of the main list to a tab delimited list
    LOOP AT im_main_list INTO me->main_list_line.
      CLEAR: lp_string.
      DO.
        ASSIGN COMPONENT sy-index OF STRUCTURE me->main_list_line TO <l_fs>.
        IF sy-subrc <> 0.
          EXIT.
        ELSE.
          IF sy-index = 1.
            lp_string = <l_fs>.
          ELSE.
            DESCRIBE FIELD <l_fs> TYPE lp_type COMPONENTS lp_com.
            IF lp_type NA co_non_charlike.
              CONCATENATE lp_string tp_tab <l_fs> INTO lp_string.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDDO.
      APPEND lp_string TO ex_tab_delimited.
    ENDLOOP.
  ENDMETHOD.                    "main_to_tab_delimited

  METHOD display_transport.
    CALL FUNCTION 'TMS_UI_SHOW_TRANSPORT_REQUEST'
      EXPORTING
        iv_request                    = im_trkorr
      EXCEPTIONS
        show_transport_request_failed = 1
        OTHERS                        = 2.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.
    LEAVE SCREEN.
  ENDMETHOD.                    "display_transport

  METHOD display_user.
    DATA: lp_return   TYPE bapiret2.
    CALL FUNCTION 'BAPI_USER_DISPLAY'
      EXPORTING
        username = im_user
      IMPORTING
        return   = lp_return.
    IF lp_return-type CA 'EA'.
      CALL FUNCTION 'SUSR_SHOW_USER_DETAILS'
        EXPORTING
          bname = im_user.
    ENDIF.
  ENDMETHOD.                    "display_user

  METHOD display_docu.
    DATA: lp_dokl_object TYPE doku_obj.
    MOVE: im_trkorr  TO lp_dokl_object.
    me->docu_call( EXPORTING im_object = lp_dokl_object ).
    me->check_documentation( EXPORTING im_trkorr = im_trkorr
                             CHANGING  ch_table  = me->main_list ).
  ENDMETHOD.                    "display_docu

  METHOD refresh_alv.
*   Declaration for Top of List settings
    DATA: lr_form_element TYPE REF TO cl_salv_form_element.

    me->top_of_page( IMPORTING ex_form_element = lr_form_element ).
    rf_table->set_top_of_list( lr_form_element ).
    me->set_color( ).
    me->alv_set_tooltips( EXPORTING im_table = rf_table ).
    rf_table->refresh( ).
  ENDMETHOD.                    "refresh_alv

  METHOD tab_delimited_to_main.
    TYPES: BEGIN OF lty_upl_line,
             field          TYPE fieldname,
             value          TYPE string,
           END OF lty_upl_line.
    DATA: lt_upl_line       TYPE TABLE OF lty_upl_line.
    DATA: ls_upl_line       TYPE lty_upl_line.
    DATA: lt_main_upl       TYPE tt_request_details.
    DATA: ls_main_line_upl  TYPE ty_request_details.
    DATA: lp_record         TYPE string.
    DATA: ls_main           TYPE ty_request_details.
    DATA: lp_type           TYPE char01.
    DATA: lp_com            TYPE i.
    FIELD-SYMBOLS: <l_fs>   TYPE ANY.
*   Determine the number of fields in the structure
    DATA: l_o_tabledescr         TYPE REF TO cl_abap_tabledescr.
    DATA: l_o_typedescr          TYPE REF TO cl_abap_typedescr.
    DATA: l_o_structdescr        TYPE REF TO cl_abap_structdescr.
    DATA: l_s_abap_compdescr_tab TYPE abap_compdescr.
    DATA: ls_component           TYPE abap_compdescr.
    TRY.
        l_o_typedescr = cl_abap_tabledescr=>describe_by_data( p_data = me->main_list ).
        l_o_tabledescr ?= l_o_typedescr.
        l_o_structdescr ?= l_o_tabledescr->get_table_line_type( ).
      CATCH cx_sy_move_cast_error INTO rf_root.
        me->handle_error( EXPORTING rf_oref = rf_root ).
      CATCH cx_root INTO rf_root.
        me->handle_error( EXPORTING rf_oref = rf_root ).
    ENDTRY.
*   First line contains the name of the fields
*   Now modify the lines of the main list to a tab delimited list
    READ TABLE im_tab_delimited INDEX 1
                                INTO  lp_record.
*   Build list of fields, in order of uploaded file
    DO.
      SPLIT lp_record AT tp_tab INTO ls_upl_line-field lp_record.
      IF lp_record IS INITIAL.
        EXIT.
      ENDIF.
      APPEND ls_upl_line TO lt_upl_line.
    ENDDO.
    LOOP AT im_tab_delimited FROM 2                "Skip the header line
                             INTO lp_record.
      CLEAR: ls_upl_line.
*     First put all values for this record in the value table
*     Build list of fields, in order of uploaded file
      DO.
*       Get the corresponding line from the table containing
*       the fields and values (to be updated with the value)
        READ TABLE lt_upl_line INDEX sy-index
                               INTO  ls_upl_line.
        SPLIT lp_record AT tp_tab INTO ls_upl_line-value lp_record.
        IF lp_record IS INITIAL.
          EXIT.
        ELSE.
          MODIFY lt_upl_line FROM  ls_upl_line
                             INDEX sy-tabix
                             TRANSPORTING value.
        ENDIF.
      ENDDO.
*     Map the fields from the uploaded line to the correct component
*     of the main list
      DO.
*       Get corresponding fieldname for file column
        READ TABLE lt_upl_line INTO  ls_upl_line
                               INDEX sy-index.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.
*       Get information about where the column is in the structure
*       Get the lenght and position from the structure definition:
        READ TABLE l_o_structdescr->components
                   INTO ls_component
                   WITH KEY name = ls_upl_line-field.
        IF sy-subrc = 0.
          TRY.
              ASSIGN COMPONENT ls_component-name OF STRUCTURE ls_main_line_upl TO <l_fs>.
            CATCH cx_root INTO rf_root.
          ENDTRY.
          IF sy-subrc <> 0.
            EXIT.
          ELSE.
            DESCRIBE FIELD <l_fs> TYPE lp_type COMPONENTS lp_com.
            IF lp_type NA co_non_charlike.
              TRY .
                  <l_fs> = ls_upl_line-value.
                CATCH cx_root INTO rf_root.
              ENDTRY.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDDO.
      APPEND ls_main_line_upl TO lt_main_upl.
      CLEAR: ls_main_line_upl.
    ENDLOOP.

*   Now move the lines of the uploaded list to the main list and
*   if another file is added to the main list (&ADD_FILE), then
*   Automatically RE-Check the objects in the existing main list
    DESCRIBE TABLE lt_main_upl LINES me->total.

    LOOP AT lt_main_upl INTO ls_main.
      me->progress_indicator( EXPORTING im_counter = sy-tabix
                                        im_object  = ''
                                        im_total   = me->total
                                        im_text    = 'records read and added.'(022)
                                        im_flag    = abap_true ).
*     Check if the record is already in the main list:
      READ TABLE main_list WITH KEY trkorr     = ls_main-trkorr
                                    object     = ls_main-object
                                    obj_name   = ls_main-obj_name
                                    keyobject  = ls_main-keyobject
                                    keyobjname = ls_main-keyobjname
                                    tabkey     = ls_main-tabkey
                           TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
*       If a file is uploaded to be merged (&ADD_FILE), then we need to
*       check all the records that are going to be added to the main list,
*       as well as all the records in the main list that contain an object
*       also in the loaded list:
        IF sy-ucomm  = '&ADD_FILE'.
          ls_main-flag = abap_true.
          LOOP AT main_list INTO  me->main_list_line
                            WHERE object     = ls_main-object
                            AND   obj_name   = ls_main-obj_name
                            AND   keyobject  = ls_main-keyobject
                            AND   keyobjname = ls_main-keyobjname
                            AND   tabkey     = ls_main-tabkey. "#EC CI_NESTED
            me->main_list_line-flag = abap_true.
            MODIFY main_list FROM me->main_list_line.
          ENDLOOP.
        ENDIF.
        APPEND ls_main TO main_list.
      ELSE.
        CHECK 1 = 1.
      ENDIF.
    ENDLOOP.
    me->sort_main_list( ).
  ENDMETHOD.                    "tab_delimited_to_main

  METHOD gui_upload.
    DATA: lt_tab_delimited TYPE table_of_strings.
    DATA: lt_temp_table    TYPE table_of_strings.
    CALL METHOD cl_gui_frontend_services=>gui_upload
      EXPORTING
        filename                = im_filename
        filetype                = 'ASC'
      CHANGING
        data_tab                = lt_temp_table
      EXCEPTIONS
        file_open_error         = 1
        file_read_error         = 2
        no_batch                = 3
        gui_refuse_filetransfer = 4
        invalid_type            = 5
        no_authority            = 6
        unknown_error           = 7
        bad_data_format         = 8
        header_not_allowed      = 9
        separator_not_allowed   = 10
        header_too_long         = 11
        unknown_dp_error        = 12
        access_denied           = 13
        dp_out_of_memory        = 14
        disk_full               = 15
        dp_timeout              = 16
        not_supported_by_gui    = 17
        error_no_gui            = 18
        OTHERS                  = 19.
    IF sy-subrc <> 0.
      ex_cancelled = abap_true.
      CASE sy-subrc.
        WHEN 1.
          IF im_filename IS INITIAL.
            MESSAGE i000(db) WITH 'Cancelled by user'(031).
          ELSE.
            MESSAGE e000(db) WITH 'Error occurred'(029).
          ENDIF.
        WHEN OTHERS.
          MESSAGE e000(db) WITH 'Error occurred'(029).
      ENDCASE.
    ELSE.
      lt_tab_delimited[] = lt_temp_table[].
*     Now convert the tab delimited file to the main list field order:
      me->tab_delimited_to_main( EXPORTING im_tab_delimited = lt_tab_delimited
                                 IMPORTING ex_main_list     = me->main_list ).
      DESCRIBE TABLE me->main_list LINES me->total.
*     Always reset the Check flag when uploading.
      me->clear_flags( ).
      LOOP AT me->main_list INTO me->main_list_line.
        me->progress_indicator( EXPORTING im_counter = sy-tabix
                                          im_object  = me->main_list_line-obj_name
                                          im_total   = me->total
                                          im_text    = 'records checked (documentation)'(023)
                                          im_flag    = abap_true ).
        me->check_documentation( EXPORTING im_trkorr = me->main_list_line-trkorr
                                 CHANGING  ch_table  = me->main_list ).
      ENDLOOP.
    ENDIF.
*   A simple check on the internal table. If a warning is found, then
*   we assume that the check parameter needs to be switched ON.
    LOOP AT me->main_list INTO me->main_list_line
                          WHERE NOT warning_lvl IS INITIAL.
      me->set_check_flag( ).
      EXIT.
    ENDLOOP.
*   Check if the Checked icon needs to be cleared:
    IF me->clear_checked = abap_true.
      LOOP AT me->main_list INTO  me->main_list_line
                            WHERE checked = co_checked.
        CLEAR: me->main_list_line-checked.
        MODIFY me->main_list FROM  me->main_list_line
                             INDEX sy-tabix.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.                    "gui_upload

  METHOD check_if_in_list.
    DATA: lp_tabix   TYPE i.
    CLEAR: ex_line.
* This subroutine checks if the conflicting transport/object is found
* further down in the list (in a later transport):
    lp_tabix = im_tabix + 1.
    LOOP AT me->main_list INTO  ex_line FROM lp_tabix
                          WHERE trkorr     =  im_line-trkorr
                          AND   object     =  im_line-object
                          AND   obj_name   =  im_line-obj_name
                          AND   keyobject  =  im_line-keyobject
                          AND   keyobjname =  im_line-keyobjname
                          AND   tabkey     =  im_line-tabkey
                          AND   prd        <> co_okay.
      EXIT.
    ENDLOOP.
  ENDMETHOD.                    "check_if_in_list

  METHOD check_if_same_object.
*   Although there is already a warning (older transport not moved or
*   newer transport was moved), it must be the exact same object. If it's
*   an entry in a table, it should not be checked if the table was
*   changed, but if it's the same entry that was changed... This perform
*   check the key entries.
    DATA:  ls_e071k TYPE e071k.
    CLEAR: ex_tabkey,
           ex_return.
*   The check on object (if the same) can either be done on key level (for
*   tables) or just on object level... Depends on the OBJFUNC field.

    CASE im_line-objfunc.
      WHEN 'K'. "Key fields available
        SELECT * FROM e071k
                 INTO ls_e071k UP TO 1 ROWS
                 WHERE trkorr = im_newer_older-trkorr
                 AND   tabkey = im_line-tabkey.
        ENDSELECT.
*       Now check if in both transports, an object exists with the
*       same key:
        IF ls_e071k IS INITIAL.
*         No key found. Treat as if it's the same object...
          IF im_newer_older-object   = im_line-object AND
             im_newer_older-obj_name = im_line-obj_name.
            ex_return = abap_true.
          ENDIF.
        ELSE.
*         There are records to be compared, only if the record is for the
*         same key, accept the warning as true (return = 'X').
          ex_return = abap_true.
          CONCATENATE ls_e071k-tabkey ' ('
                      ls_e071k-objname ')'
                      INTO ex_tabkey.
        ENDIF.
      WHEN OTHERS.
        IF im_newer_older-object   = im_line-object AND
           im_newer_older-obj_name = im_line-obj_name.
          ex_return = abap_true.
        ENDIF.
    ENDCASE.
  ENDMETHOD.                    "check_if_same_object

  METHOD check_documentation.
    DATA: ls_doktl  TYPE doktl.      "Documentation - text lines
    MOVE: im_trkorr TO tp_dokl_object.
    SELECT * FROM  doktl
             UP TO 1 ROWS
             INTO  ls_doktl
             WHERE id        =  'TA'
             AND   object    =  tp_dokl_object
             AND   typ       =  'T'
             AND   dokformat <> 'L'
             AND   doktext   <> ''.
    ENDSELECT.
    IF ls_doktl IS NOT INITIAL.
*     There is documentation: Display Doc Icon
      me->main_list_line-info = co_docu.
    ELSE.
*     There is no documentation: Remove Doc Icon
      CLEAR me->main_list_line-info.
    ENDIF.
    MODIFY ch_table FROM me->main_list_line
                    TRANSPORTING info
                    WHERE trkorr = im_trkorr.
  ENDMETHOD.                    "check_documentation

  METHOD alv_init.
    CLEAR: rf_table.
    TRY.
        CALL METHOD cl_salv_table=>factory
          EXPORTING
            list_display = if_salv_c_bool_sap=>false
          IMPORTING
            r_salv_table = rf_table
          CHANGING
            t_table      = me->main_list.
      CATCH cx_salv_msg INTO rf_root.
        me->handle_error( EXPORTING rf_oref = rf_root ).
    ENDTRY.
    IF rf_table IS INITIAL.
      MESSAGE 'Error Creating ALV Grid'(t03) TYPE 'A' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.                    "alv_init

  METHOD alv_xls_init.
    TRY.
        CALL METHOD cl_salv_table=>factory
          EXPORTING
            list_display = if_salv_c_bool_sap=>false
          IMPORTING
            r_salv_table = ex_rf_table
          CHANGING
            t_table      = ch_table.
      CATCH cx_salv_msg INTO rf_root.
        me->handle_error( EXPORTING rf_oref = rf_root ).
    ENDTRY.
    IF rf_table_xls IS INITIAL.
      MESSAGE 'Error Creating ALV Grid'(t03) TYPE 'A' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.                    "alv_init

  METHOD set_color.
*   Color Structure of columns
    DATA: ta_scol                     TYPE lvc_t_scol.
    DATA: st_scol                     TYPE lvc_s_scol.
    FIELD-SYMBOLS: <fs_main> TYPE ty_request_details.
    LOOP AT me->main_list ASSIGNING <fs_main>.
*     Init
      REFRESH: ta_scol.
      CLEAR  : st_scol.
      MOVE ta_scol TO <fs_main>-t_color.
*     Add color
      IF <fs_main>-warning_rank >= co_info_rank.
        REFRESH: ta_scol.
        CLEAR  : st_scol.
        MOVE 3             TO st_scol-color-col.
        MOVE 0             TO st_scol-color-int.
        MOVE 0             TO st_scol-color-inv.
        MOVE 'WARNING_TXT' TO st_scol-fname.
        APPEND st_scol     TO ta_scol.
        MOVE 'WARNING_LVL' TO st_scol-fname.
        APPEND st_scol     TO ta_scol.
        MOVE ta_scol       TO <fs_main>-t_color.
      ENDIF.
      IF <fs_main>-warning_rank >= co_warn_rank.
        REFRESH: ta_scol.
        CLEAR  : st_scol.
        MOVE 7             TO st_scol-color-col.
        MOVE 0             TO st_scol-color-int.
        MOVE 0             TO st_scol-color-inv.
        MOVE 'WARNING_TXT' TO st_scol-fname.
        APPEND st_scol     TO ta_scol.
        MOVE 'WARNING_LVL' TO st_scol-fname.
        APPEND st_scol     TO ta_scol.
        MOVE ta_scol       TO <fs_main>-t_color.
      ENDIF.
      IF <fs_main>-warning_rank >= co_error_rank.
        REFRESH: ta_scol.
        CLEAR  : st_scol.
        MOVE 6             TO st_scol-color-col.
        MOVE 0             TO st_scol-color-int.
        MOVE 0             TO st_scol-color-inv.
        MOVE 'WARNING_TXT' TO st_scol-fname.
        APPEND st_scol     TO ta_scol.
        MOVE 'WARNING_LVL' TO st_scol-fname.
        APPEND st_scol     TO ta_scol.
        MOVE ta_scol       TO <fs_main>-t_color.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.                    "set_color

  METHOD set_check_flag.
    IF im_check_flag IS SUPPLIED.
      me->check_flag = im_check_flag.
    ELSE.
      me->check_flag = abap_true.
    ENDIF.
  ENDMETHOD.                    "set_check_flag

  METHOD set_check_ddic.
    IF im_check_ddic IS SUPPLIED.
      me->check_ddic = im_check_ddic.
    ELSE.
      me->check_ddic = abap_true.
    ENDIF.
  ENDMETHOD.                    "set_ddic_check

  METHOD set_check_tabkeys.
    IF im_check_tabkeys IS SUPPLIED.
      me->check_tabkeys = im_check_tabkeys.
    ELSE.
      me->check_tabkeys = abap_true.
    ENDIF.
  ENDMETHOD.                    "set_check_tabkeys

  METHOD set_clear_checked.
    IF im_clear_checked IS SUPPLIED.
      me->clear_checked = im_clear_checked.
    ELSE.
      me->clear_checked = abap_true.
    ENDIF.
  ENDMETHOD.                    "set_clear_checked

  METHOD set_skip_buffer_chk.
    IF im_skip_buffer_chk IS SUPPLIED.
      me->skip_buffer_chk = im_skip_buffer_chk.
    ELSE.
      me->skip_buffer_chk = abap_true.
    ENDIF.
  ENDMETHOD.                    "set_skip_buffer_chk

  METHOD set_trkorr_range.
    me->trkorr_range = im_trkorr_range.
  ENDMETHOD.                    "set_trkorr_range

  METHOD set_project_range.
    me->project_range = im_project_range.
  ENDMETHOD.                    "set_trkorr_range

  METHOD set_date_range.
    me->date_range = im_date_range.
  ENDMETHOD.                    "set_trkorr_range

  METHOD set_excluded_objects.
    me->excluded_objects = im_excluded_objects.
  ENDMETHOD.                    "set_trkorr_range

  METHOD set_search_string.
    me->search_string = im_search_string.
  ENDMETHOD.                    "set_search_string

  METHOD set_user_layout.
    me->user_layout = im_user_layout.
  ENDMETHOD.                    "set_user_layout

  METHOD set_process_type.
    me->process_type = im_process_type.
  ENDMETHOD.                    "set_process_type

  METHOD  set_skiplive.
    IF im_skiplive IS SUPPLIED.
      me->skiplive = im_skiplive.
    ELSE.
      me->skiplive = abap_true.
    ENDIF.
  ENDMETHOD.                    "set_skiplive

  METHOD set_filename.
    me->filename = im_filename.
  ENDMETHOD.                    "set_filename

  METHOD set_systems.
    me->dev_system = im_dev_system.
    me->qas_system = im_qas_system.
    me->prd_system = im_prd_system.
  ENDMETHOD.                    "set_systems

  METHOD set_building_conflict_popup.
    IF im_building_conflict_popup IS SUPPLIED.
      me->building_conflict_popup = im_building_conflict_popup.
    ELSE.
      me->building_conflict_popup = abap_true.
    ENDIF.
  ENDMETHOD.                    "set_building_conflict_popup

  METHOD alv_set_properties.
*   Declaration for ALV Columns
    DATA: lr_columns_table       TYPE REF TO cl_salv_columns_table.
    DATA: lt_t_column_ref        TYPE salv_t_column_ref.
    DATA: lr_functions_list      TYPE REF TO cl_salv_functions_list.
*   Declaration for Top of List settings
    DATA: lr_form_element        TYPE REF TO cl_salv_form_element.
*   Declaration for Layout Settings
    DATA: lr_layout              TYPE REF TO cl_salv_layout.
    DATA: ls_layout_key          TYPE salv_s_layout_key.
*   Declaration for Aggregate Function Settings
    DATA: lr_aggregations        TYPE REF TO cl_salv_aggregations.
*   Declaration for Sort Function Settings
    DATA: lr_sorts               TYPE REF TO cl_salv_sorts.
*   Declaration for Table Selection settings
    DATA: lr_selections          TYPE REF TO cl_salv_selections.
*   Declaration for Global Display Settings
    DATA: lr_display_settings    TYPE REF TO cl_salv_display_settings.
    DATA: lp_version             TYPE char10.
    DATA: lp_title               TYPE lvc_title.
    DATA: lp_class               TYPE xuclass.

    FIELD-SYMBOLS: <table>       TYPE REF TO cl_salv_table.
    ASSIGN im_table TO <table>.

*   Set status
*   Copy the status from program SAPLSLVC_FULLSCREEN and delete the
*   buttons you do not need. Add extra buttons for use in USER_COMMAND
    <table>->set_screen_status( pfstatus = 'STANDARD_FULLSCREEN'
                                report   = sy-repid ).
*   Get functions details
    lr_functions_list = <table>->get_functions( ).
*   Activate All Buttons in Tool Bar
    lr_functions_list->set_all( if_salv_c_bool_sap=>true ).
*   If necessary, deactivate functions
    IF check_flag = abap_false.
      TRY.
          lr_functions_list->set_function( name    = 'RECHECK'
                                           boolean = if_salv_c_bool_sap=>false ).
        CATCH cx_root INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.
    ENDIF.
*   Layout Settings
    CLEAR: lr_layout.
    CLEAR: ls_layout_key.
*   Set Report ID as Layout Key
    MOVE sy-repid TO ls_layout_key-report.
*   Get Layout of Table
    lr_layout = <table>->get_layout( ).
*   To allow DEFAULT layout
    lr_layout->set_default( if_salv_c_bool_sap=>true ).
*   Set Report Id to Layout
    lr_layout->set_key( ls_layout_key ).
*   If the user is part of a specific class, then the user can
*   maintain all layouts. Otherwise only the user specific layout.
    SELECT SINGLE class FROM  usr02
                        INTO  lp_class
                        WHERE bname = sy-uname.
*   Changed to specific users...
    IF lp_class = 'SB'.
      lp_save_restriction = if_salv_c_layout=>restrict_none.
    ELSE.
      lp_save_restriction = if_salv_c_layout=>restrict_user_dependant.
    ENDIF.
*   If the flag is set the default layout will be the default user
*   specific layout
    IF me->user_layout = abap_false.
      lr_layout->set_initial_layout( '/DEFAULT' ).
    ENDIF.

    lr_layout->set_save_restriction( lp_save_restriction ).
*   Global Display Settings
    CLEAR: lr_display_settings.
*   Build title:
*   Get version to display in title:
    SELECT datum FROM  vrsd
                 INTO  vrsd-datum UP TO 1 ROWS
                 WHERE objtype = 'REPS'
                 AND   objname = sy-repid.
      WRITE vrsd-datum TO lp_version.
    ENDSELECT.
    IF lp_version IS NOT INITIAL.
      SELECT SINGLE text FROM  d347t INTO lp_title
                         WHERE progname = sy-repid
                         AND   sprsl    = sy-langu
                         AND   obj_code = '001'.
      IF sy-subrc <> 0.
        SELECT SINGLE text FROM  d347t INTO lp_title
                           WHERE progname = sy-repid
                           AND   sprsl    = 'EN'
                           AND   obj_code = '001'.
      ENDIF.
    ENDIF.
*   Set title
    IF lp_title IS INITIAL.
      lp_title = sy-title.
    ELSE.
      REPLACE '&1' WITH lp_version INTO lp_title.
    ENDIF.
*   Global display settings
    lr_display_settings = <table>->get_display_settings( ).
*   Activate Striped Pattern
    lr_display_settings->set_striped_pattern( if_salv_c_bool_sap=>true ).
*   Report header
    lr_display_settings->set_list_header( lp_title ).
*   Aggregate Function Settings
    lr_aggregations = <table>->get_aggregations( ).
*   Sort Functions
    lr_sorts = <table>->get_sorts( ).
    IF lr_sorts IS NOT INITIAL.
      TRY.
          lr_sorts->add_sort( columnname = 'AS4DATE'
                              position = 1
                              sequence   = if_salv_c_sort=>sort_up
                              subtotal   = if_salv_c_bool_sap=>false
                              obligatory = if_salv_c_bool_sap=>false ).
        CATCH cx_salv_not_found INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
        CATCH cx_salv_existing INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
        CATCH cx_salv_data_error INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.
      TRY.
          lr_sorts->add_sort( columnname = 'AS4TIME'
                              position = 2
                              sequence   = if_salv_c_sort=>sort_up
                              subtotal   = if_salv_c_bool_sap=>false
                              group      = if_salv_c_sort=>group_none
                              obligatory = if_salv_c_bool_sap=>false ).
        CATCH cx_salv_not_found INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
        CATCH cx_salv_existing INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
        CATCH cx_salv_data_error INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.
    ENDIF.
*   Table Selection Settings
    lr_selections = <table>->get_selections( ).
    IF lr_selections IS NOT INITIAL.
*   Allow row Selection
      lr_selections->set_selection_mode(
                     if_salv_c_selection_mode=>row_column ).
    ENDIF.
*   Event Register settings
    rf_events_table = <table>->get_event( ).
    CREATE OBJECT rf_handle_events.
    SET HANDLER rf_handle_events->on_function_click FOR rf_events_table.
    SET HANDLER rf_handle_events->on_double_click   FOR rf_events_table.
    SET HANDLER rf_handle_events->on_link_click     FOR rf_events_table.
*   Get the columns from ALV Table
    lr_columns_table = <table>->get_columns( ).
    IF lr_columns_table IS NOT INITIAL.
      REFRESH : lt_t_column_ref.
      lt_t_column_ref = lr_columns_table->get( ).
*     Get columns properties
      lr_columns_table->set_optimize( if_salv_c_bool_sap=>true ).
      lr_columns_table->set_key_fixation( if_salv_c_bool_sap=>true ).
      TRY.
          lr_columns_table->set_color_column( 'T_COLOR' ).
        CATCH cx_salv_data_error INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.
*     Individual Column Properties.
      me->column_settings( EXPORTING im_column_ref         = lt_t_column_ref
                                     im_rf_columns_table   = lr_columns_table
                                     im_table              = <table> ).
    ENDIF.
*   Skip the following code for the conflicts popups
    IF <table> <> rf_conflicts.
*     Top of List settings
      me->top_of_page( IMPORTING ex_form_element = lr_form_element ).
      <table>->set_top_of_list( lr_form_element ).
    ENDIF.
  ENDMETHOD.                    "alv_set_properties

  METHOD alv_set_tooltips.
*   Fill the symbols, colors in to table and set tooltips
    DATA: tooltips TYPE REF TO cl_salv_tooltips.
    DATA: settings TYPE REF TO cl_salv_functional_settings.
    DATA: value    TYPE char128.
    DATA: lp_text  TYPE lvc_tip.
    FIELD-SYMBOLS: <outtab> TYPE ty_request_details.
    FREE settings.
    FREE tooltips.
    settings = im_table->get_functional_settings( ).
    tooltips = settings->get_tooltips( ).
    TRY.
        lp_text = 'Newer version in Acceptance'(w23).
        tooltips->add_tooltip( type    = cl_salv_tooltip=>c_type_symbol
                               value   = '@0S@'
                               tooltip = lp_text ).
      CATCH cx_salv_existing INTO rf_root.
    ENDTRY.
    TRY.
        lp_text = 'Previous transport not transported'(w17).
        tooltips->add_tooltip( type    = cl_salv_tooltip=>c_type_symbol
                               value   = '@5D@'
                               tooltip = lp_text ).
      CATCH cx_salv_existing INTO rf_root.
    ENDTRY.
    TRY.
        lp_text = 'All conflicts are dealt with by the list'(w04).
        tooltips->add_tooltip( type    = cl_salv_tooltip=>c_type_symbol
                               value   = '@AI@'
                               tooltip = lp_text ).
      CATCH cx_salv_existing INTO rf_root.
    ENDTRY.
    TRY.
        lp_text = 'Marked for re-import to Production'(w18).
        tooltips->add_tooltip( type    = cl_salv_tooltip=>c_type_symbol
                               value   = '@K3@'
                               tooltip = lp_text ).
      CATCH cx_salv_existing INTO rf_root.
    ENDTRY.
    TRY.
        lp_text = 'Newer version in production!'(w01).
        tooltips->add_tooltip( type    = cl_salv_tooltip=>c_type_symbol
                               value   = '@F1@'
                               tooltip = lp_text ).
      CATCH cx_salv_existing INTO rf_root.
    ENDTRY.
    TRY.
        lp_text = 'Object missing in List and Production!'(w05).
        tooltips->add_tooltip( type    = cl_salv_tooltip=>c_type_symbol
                               value   = '@CY@'
                               tooltip = lp_text ).
      CATCH cx_salv_existing INTO rf_root.
    ENDTRY.
  ENDMETHOD.                    "alv_set_tooltips

  METHOD alv_output.
*   Display the ALV output
    CALL METHOD rf_table->display.
  ENDMETHOD.                    "alv_output

  METHOD alv_xls_output.
*   Display the ALV output
    CALL METHOD rf_table_xls->display.
  ENDMETHOD.                    "alv_output

  METHOD column_settings.
    TYPES: BEGIN OF lty_field_ran,
             sign   TYPE c LENGTH 1,
             option TYPE c LENGTH 2,
             low    TYPE fieldname,
             high   TYPE fieldname,
           END OF lty_field_ran.

    DATA: ls_reference        TYPE salv_s_ddic_reference.
    DATA: ls_s_column_ref     TYPE salv_s_column_ref.
    DATA: lr_column_table     TYPE REF TO cl_salv_column_table.
    DATA: st_colo             TYPE lvc_s_colo.
*   Declaration for Aggregate Function Settings
    DATA: lr_aggregations     TYPE REF TO cl_salv_aggregations.
*   Remove some columns for the XLS output
    DATA: lra_fieldname       TYPE RANGE OF lty_field_ran.
    DATA: ls_fieldname        TYPE lty_field_ran.
    DATA: lp_return           TYPE abap_bool.
*   Hide columns when empty
    DATA: lra_hide_when_empty TYPE RANGE OF lty_field_ran.
    DATA: ls_hide_when_empty  TYPE lty_field_ran.
*   Texts
    DATA: lp_short_text       TYPE char10.
    DATA: lp_medium_text      TYPE char20.
    DATA: lp_long_text        TYPE char40.

    DATA: lp_sys_s TYPE REF TO data.
    DATA: lp_sys_m TYPE REF TO data.
    DATA: lp_sys_l TYPE REF TO data.
    FIELD-SYMBOLS: <text_s> TYPE scrtext_s.
    FIELD-SYMBOLS: <text_m> TYPE scrtext_m.
    FIELD-SYMBOLS: <text_l> TYPE scrtext_l.

* Instantiate data references for column headers
    CREATE DATA lp_sys_s TYPE scrtext_s.
    CREATE DATA lp_sys_m TYPE scrtext_m.
    CREATE DATA lp_sys_l TYPE scrtext_l.
    ASSIGN lp_sys_s->* TO <text_s>.
    ASSIGN lp_sys_m->* TO <text_m>.
    ASSIGN lp_sys_l->* TO <text_l>.

*   Build range for all unwanted columns:
    CASE im_table.
      WHEN rf_table_xls.
        ls_fieldname-option = 'EQ'.
        ls_fieldname-sign = 'I'.
        ls_fieldname-low = 'CHECKED'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'OBJECT'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'OBJ_NAME'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'OBJKEY'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'KEYOBJECT'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'KEYOBJNAME'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'TABKEY'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'PGMID'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'DEV'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'QAS'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'PRD'.
        APPEND ls_fieldname TO lra_fieldname.
        ls_fieldname-low = 'STATUS_TEXT'.
        APPEND ls_fieldname TO lra_fieldname.
      WHEN rf_table.
        ls_fieldname-option = 'EQ'.
        ls_fieldname-sign = 'I'.
        ls_fieldname-low = 'RE_IMPORT'.
        APPEND ls_fieldname TO lra_fieldname.
    ENDCASE.
*   Always remove the following colums, regardless of which table is used
    ls_fieldname-option = 'EQ'.
    ls_fieldname-sign = 'I'.
    ls_fieldname-low = 'TRSTATUS'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'TRFUNCTION'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'TROBJ_NAME  '.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'FLAG'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'OBJFUNC'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'CHECKED_BY'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'WARNING_RANK'.
    APPEND ls_fieldname TO lra_fieldname.

*   Hide when empty
    ls_hide_when_empty-option = 'EQ'.
    ls_hide_when_empty-sign   = 'I'.
    ls_hide_when_empty-low    = 'OBJKEY'.
    APPEND ls_hide_when_empty TO lra_hide_when_empty.
    ls_hide_when_empty-low    = 'KEYOBJECT'.
    APPEND ls_hide_when_empty TO lra_hide_when_empty.
    ls_hide_when_empty-low    = 'KEYOBJNAME'.
    APPEND ls_hide_when_empty TO lra_hide_when_empty.
    ls_hide_when_empty-low    = 'TABKEY'.
    APPEND ls_hide_when_empty TO lra_hide_when_empty.
    ls_hide_when_empty-low    = 'PROJECT'.
    APPEND ls_hide_when_empty TO lra_hide_when_empty.
    ls_hide_when_empty-low    = 'PROJECT_DESCR'.
    APPEND ls_hide_when_empty TO lra_hide_when_empty.

    LOOP AT im_column_ref INTO ls_s_column_ref.
      TRY.
          lr_column_table ?=
            im_rf_columns_table->get_column( ls_s_column_ref-columnname ).
        CATCH cx_salv_not_found INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.
      IF lr_column_table IS NOT INITIAL.
*       Make Mandt column invisible
        IF lr_column_table->get_ddic_datatype( ) = 'CLNT'.
          lr_column_table->set_technical( if_salv_c_bool_sap=>true ).
        ENDIF.
*       Create Aggregate function total for All Numeric/Currency Fields
        IF lr_column_table->get_ddic_inttype( ) EQ 'P' OR
           lr_column_table->get_ddic_datatype( ) EQ 'CURR'.
          IF lr_aggregations IS NOT INITIAL.
            TRY.
                lr_aggregations->add_aggregation(
                                  columnname = ls_s_column_ref-columnname
                                  aggregation = if_salv_c_aggregation=>total ).
              CATCH cx_salv_data_error INTO rf_root.
                me->handle_error( EXPORTING rf_oref = rf_root ).
              CATCH cx_salv_not_found INTO rf_root.
                me->handle_error( EXPORTING rf_oref = rf_root ).
              CATCH cx_salv_existing INTO rf_root.
                me->handle_error( EXPORTING rf_oref = rf_root ).
            ENDTRY.
          ENDIF.
        ENDIF.
*       Create Check box for fields with domain "XFELD"
        IF lr_column_table->get_ddic_domain( ) EQ 'XFELD'.
          lr_column_table->set_cell_type( if_salv_c_cell_type=>checkbox ).
        ENDIF.
*       Set color to Date Columns
        IF lr_column_table->get_ddic_datatype( ) EQ 'DATS' OR
           lr_column_table->get_ddic_datatype( ) EQ 'TIMS'.
          CLEAR: st_colo.
          MOVE 2 TO st_colo-col.
          MOVE 1 TO st_colo-int.
          MOVE 1 TO st_colo-inv.
          lr_column_table->set_color( st_colo ).
        ENDIF.
*       Remove columns that are not required
        IF lr_column_table->get_columnname( ) IN lra_fieldname.
          lr_column_table->set_technical( if_salv_c_bool_sap=>true ).
        ENDIF.
*       Remove columns that are not required when empty
        IF lr_column_table->get_columnname( ) IN lra_hide_when_empty.
          lp_return = me->is_empty_column( im_column = ls_s_column_ref-columnname
                                                im_table  = main_list ).
          IF lp_return = abap_true.
            lr_column_table->set_technical( if_salv_c_bool_sap=>true ).
          ENDIF.
        ENDIF.
        CASE lr_column_table->get_columnname( ).
          WHEN 'TRKORR'.
*           Add Hotspot & Hyper Link
            lr_column_table->set_cell_type( if_salv_c_cell_type=>hotspot ).
            lr_column_table->set_key( if_salv_c_bool_sap=>true ).
          WHEN 'OBJ_NAME'.
*           Add Hotspot & Hyper Link
            lr_column_table->set_cell_type( if_salv_c_cell_type=>hotspot ).
          WHEN 'CHECKED'.
            IF check_flag = abap_true.
              ls_reference-table = 'KGALK'.
              ls_reference-field = 'CHECKED'.
              lr_column_table->set_ddic_reference( ls_reference ).
              lr_column_table->set_alignment( if_salv_c_alignment=>centered ).
            ELSE.
              lr_column_table->set_technical( ).
            ENDIF.
          WHEN 'INFO'.
            ls_reference-table = 'RSPRINT'.
            ls_reference-field = 'DOKU'.
            lr_column_table->set_ddic_reference( ls_reference ).
            lr_column_table->set_alignment( if_salv_c_alignment=>centered ).
            lr_column_table->set_icon( ).
          WHEN 'CHECKED_BY'.
            IF check_flag = ''.
              lr_column_table->set_technical( ).
            ENDIF.
          WHEN 'RETCODE'.
            lp_short_text = 'RC'(015).
            lp_long_text = lp_medium_text = 'Return Code'(016).
            lr_column_table->set_short_text( lp_short_text ).
            lr_column_table->set_medium_text( lp_medium_text ).
            lr_column_table->set_long_text( lp_long_text ).
          WHEN 'STATUS_TEXT'.
            lp_short_text = 'Descript.'(017).
            lp_long_text = lp_medium_text = 'Description'(018).
            lr_column_table->set_short_text( lp_short_text ).
            lr_column_table->set_medium_text( lp_medium_text ).
            lr_column_table->set_long_text( lp_long_text ).
          WHEN 'WARNING_LVL'.
            IF check_flag = abap_true.
              ls_reference-table = 'FCALV_S_RMLIFO20'.
              ls_reference-field = 'WARNING'.
              lr_column_table->set_ddic_reference( ls_reference ).
              lr_column_table->set_icon( ).
            ELSE.
              lr_column_table->set_technical( ).
            ENDIF.
          WHEN 'WARNING_TXT'.
            IF check_flag = abap_true.
              ls_reference-table = 'CSIM_ST_EXPL'.
              ls_reference-field = 'TEXT_WARNING'.
              lr_column_table->set_ddic_reference( ls_reference ).
            ELSE.
              lr_column_table->set_technical( ).
            ENDIF.
          WHEN 'PROJECT'.
            ls_reference-table = 'LOG_HEADER'.
            ls_reference-field = 'PRONR'.
            lr_column_table->set_ddic_reference( ls_reference ).
          WHEN 'STATUS'.
            ls_reference-table = 'TRHEADER'.
            ls_reference-field = 'TRSTATUS'.
            lr_column_table->set_ddic_reference( ls_reference ).
            lr_column_table->set_key( ).
          WHEN 'DEV'.
            <text_s> = me->dev_system.
            <text_m> = me->dev_system.
            <text_l> = me->dev_system.
            IF <text_s> IS ASSIGNED.
              lr_column_table->set_short_text( <text_s> ).
            ENDIF.
            IF <text_m> IS ASSIGNED.
              lr_column_table->set_medium_text( <text_m> ).
            ENDIF.
            IF <text_l> IS ASSIGNED.
              lr_column_table->set_long_text( <text_l> ).
            ENDIF.
            lr_column_table->set_icon( ).
          WHEN 'QAS'.
            <text_s> = me->qas_system.
            <text_m> = me->qas_system.
            <text_l> = me->qas_system.
            IF <text_s> IS ASSIGNED.
              lr_column_table->set_short_text( <text_s> ).
            ENDIF.
            IF <text_m> IS ASSIGNED.
              lr_column_table->set_medium_text( <text_m> ).
            ENDIF.
            IF <text_l> IS ASSIGNED.
              lr_column_table->set_long_text( <text_l> ).
            ENDIF.
            lr_column_table->set_icon( ).
          WHEN 'PRD'.
            IF <text_l> IS ASSIGNED.
              <text_s> = me->prd_system.
              <text_m> = me->prd_system.
              <text_l> = me->prd_system.
              IF <text_s> IS ASSIGNED.
                lr_column_table->set_short_text( <text_s> ).
              ENDIF.
              IF <text_m> IS ASSIGNED.
                lr_column_table->set_medium_text( <text_m> ).
              ENDIF.
              IF <text_l> IS ASSIGNED.
                lr_column_table->set_long_text( <text_l> ).
              ENDIF.
              lr_column_table->set_icon( ).
            ENDIF.
          WHEN 'RE_IMPORT'.
            lp_short_text = 'Re-import'(044).
            lp_long_text = lp_medium_text = 'Import again'(044).
            lr_column_table->set_short_text( lp_short_text ).
            lr_column_table->set_medium_text( lp_medium_text ).
            lr_column_table->set_long_text( lp_long_text ).
        ENDCASE.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.                    "column_settings

  METHOD is_empty_column.
    DATA: ls_line TYPE ty_request_details.
    FIELD-SYMBOLS: <column> TYPE ANY.
    re_is_empty = abap_true.
    LOOP AT im_table INTO ls_line.
      ASSIGN COMPONENT im_column OF STRUCTURE ls_line TO <column>.
      IF <column> IS NOT INITIAL.
        re_is_empty = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.                    "is_empty_culomn

  METHOD docu_call.
    CALL FUNCTION 'DOCU_CALL'
      EXPORTING
        id         = 'TA'
        langu      = sy-langu
        object     = im_object
      EXCEPTIONS
        wrong_name = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.
  ENDMETHOD.                    "docu_call

  METHOD determine_col_width.
* This method determines the width of a column in the detailed output
* lists (for conflicts or no-checks overviews). The length of the
* largest value is used as column width. This column width is then used
* in the fielddif table for function "STC1_POPUP_WITH_TABLE_CONTROL".
* This is done to downsize the width of the column as much as possible.
    DATA: lp_value TYPE i.
*    CLEAR: ex_colwidth.
    IF NOT im_field IS INITIAL.
      lp_value = STRLEN( im_field ).
      IF lp_value > ex_colwidth.
        ex_colwidth = lp_value.
      ENDIF.
    ENDIF.
  ENDMETHOD.                    "determine_col_width

  METHOD determine_warning_text.
    CASE im_highest_rank.
      WHEN 0.  "ICON_LED_GREEN
      WHEN 5.  "ICON_FAILURE
        ex_highest_text = lp_alert0_text.
      WHEN 6.  "ICON_FAILURE
        ex_highest_text = lp_alert1_text.
      WHEN 7.  "ICON_FAILURE
        ex_highest_text = lp_alert2_text.
      WHEN 8.  "ICON_FAILURE
        ex_highest_text  = lp_alert3_text.
      WHEN 10. "ICON_HINT
        ex_highest_text = lp_hint1_text.
      WHEN 12. "ICON_HINT
        ex_highest_text = lp_hint2_text.
      WHEN 14. "ICON_HINT
        ex_highest_text = lp_hint3_text.
      WHEN 16. "ICON_HINT
        ex_highest_text = lp_hint4_text.
      WHEN 20. "ICON_INFORMATION
        ex_highest_text = lp_info_text.
      WHEN 50. "ICON_LED_YELLOW
        ex_highest_text = lp_warn_text.
      WHEN 98. "ICON_INCOMPLETE
        ex_highest_text = lp_ddic_text.
      WHEN 99. "ICON_LED_RED
        ex_highest_text = lp_error_text.
    ENDCASE.
  ENDMETHOD.                    "determine_warning_text

  METHOD get_tps_for_same_object.

    DATA: lt_aggr_tp_list_of_objects TYPE tt_request_details.
    DATA: ls_tp_same_object          TYPE ty_request_details.
    DATA: lp_index                   TYPE sytabix.
    DATA: lp_return                  TYPE sysubrc.

    REFRESH: ex_newer.
    REFRESH: ex_older.
    CLEAR:   ex_newer.
    CLEAR:   ex_older.

*   First check if the transports for the object have already been read
*   and stored in the table. If so, then we do not need to retrieve all
*   the transports again (to speed things up a bit).
    SORT me->aggr_tp_list_of_objects BY object
                                        obj_name
                                        keyobject
                                        keyobjname
                                        tabkey.
    READ TABLE me->aggr_tp_list_of_objects
               WITH KEY object     = im_line-object
                        obj_name   = im_line-obj_name
                        keyobject  = im_line-keyobject
                        keyobjname = im_line-keyobjname
                        tabkey     = im_line-tabkey
               TRANSPORTING NO FIELDS
               BINARY SEARCH.
    IF sy-subrc <> 0.
*     The transports for this object have not been retrieved yet, so we
*     do that now:
      SELECT a~trkorr b~object  b~obj_name b~objfunc
             a~as4user a~as4date a~as4time
             FROM e070 AS a JOIN e071 AS b                  "v_e071eu
                       ON a~trkorr = b~trkorr
             INTO (ls_tp_same_object-trkorr,
                   ls_tp_same_object-object,
                   ls_tp_same_object-obj_name,
                   ls_tp_same_object-objfunc,
                   ls_tp_same_object-as4user,
                   ls_tp_same_object-as4date,
                   ls_tp_same_object-as4time)
             WHERE NOT a~trkorr IN  me->project_trkorrs
             AND   a~trfunction NE 'T'
             AND   b~obj_name   IN excluded_objects
             AND   a~strkorr    = ''
             AND   a~trkorr     LIKE me->prefix
             AND   b~object     = im_line-object
             AND   b~obj_name   = im_line-obj_name.
        APPEND ls_tp_same_object TO lt_aggr_tp_list_of_objects.
      ENDSELECT.

*   Also read from version table, because in some case, the object can
*   be part of a 'bigger' group.
*   Example 1: - a Function Module (FUNC) is transported in one
*                transport, but the entire functiongroup (FUGR) in
*                another (this also transports the FM)
*   Example 2: - A table (TABL) is part of a table definition (TABD), so
*                should also be treated as the same object.
      SELECT korrnum objtype objname
             author
             FROM  vrsd
             INNER JOIN e070 ON vrsd~korrnum EQ e070~trkorr
             INTO (ls_tp_same_object-trkorr,
                   ls_tp_same_object-object,
                   ls_tp_same_object-obj_name,
                   ls_tp_same_object-as4user)
             WHERE NOT korrnum IN  me->project_trkorrs
             AND   objname     IN excluded_objects
             AND   korrnum     <> im_line-trkorr
             AND   korrnum     LIKE me->prefix
             AND   korrnum     <> ''
             AND   objtype     =  im_line-object
             AND   objname     =  im_line-obj_name      "#EC CI_NOFIELD
             AND   e070~trfunction NE 'T'.

        APPEND ls_tp_same_object TO lt_aggr_tp_list_of_objects.
      ENDSELECT.

*     Remove duplicates:
      SORT lt_aggr_tp_list_of_objects[] BY trkorr object obj_name.
      DELETE ADJACENT DUPLICATES FROM lt_aggr_tp_list_of_objects
                                 COMPARING trkorr object obj_name.

*     If the object is a table, we need to be able to check the keys.
*     Replace the entry with all entries containing the keys.
      IF im_line-objfunc = 'K'.
        me->add_table_keys_to_list( IMPORTING table = lt_aggr_tp_list_of_objects ).
      ENDIF.

*     Now get the last date the object was imported:
      LOOP AT lt_aggr_tp_list_of_objects INTO ls_tp_same_object.
        lp_index = sy-tabix.
*       Remove all transports from a source system not known (usually an
*       SAP system, not one of our systems).
        IF NOT ls_tp_same_object-trkorr(3) IN ra_systems.
          DELETE lt_aggr_tp_list_of_objects INDEX sy-tabix.
          CONTINUE.
        ENDIF.
*       Now get the global information on the transport:
*       Get the last date the object was imported
        me->get_import_datetime_qas( EXPORTING im_trkorr  = ls_tp_same_object-trkorr
                                     IMPORTING ex_as4time = ls_tp_same_object-as4time
                                               ex_as4date = ls_tp_same_object-as4date
                                               ex_return  = lp_return ).
        IF lp_return = 0.
          MODIFY lt_aggr_tp_list_of_objects FROM ls_tp_same_object.
        ELSE.
          DELETE lt_aggr_tp_list_of_objects INDEX lp_index.
        ENDIF.
      ENDLOOP.
*     Add the newly retrieved lines to the internal table:
      APPEND LINES OF lt_aggr_tp_list_of_objects TO me->aggr_tp_list_of_objects.
    ELSE.
*     Already retrieved and stored in the list
      CHECK 1 = 1.
    ENDIF.

*   Remove duplicates:
    SORT me->aggr_tp_list_of_objects[] BY trkorr object obj_name.
    DELETE ADJACENT DUPLICATES FROM me->aggr_tp_list_of_objects
                               COMPARING trkorr object obj_name.

*   Move newer transports for this object to the relevant internal table:
    LOOP AT me->aggr_tp_list_of_objects INTO ls_tp_same_object
                                        WHERE object     =  im_line-object
                                        AND   obj_name   =  im_line-obj_name
                                        AND   keyobject  =  im_line-keyobject
                                        AND   keyobjname =  im_line-keyobjname
                                        AND   tabkey     =  im_line-tabkey
                                        AND   trkorr     <> im_line-trkorr.
*     If on the same date, check if the time is later
      IF ls_tp_same_object-as4date = im_line-as4date.
        IF ls_tp_same_object-as4time >= im_line-as4time.
          APPEND ls_tp_same_object TO ex_newer.
        ELSE.
          APPEND ls_tp_same_object TO ex_older.
        ENDIF.
      ELSE.
        IF ls_tp_same_object-as4date  > im_line-as4date.
          APPEND ls_tp_same_object TO ex_newer.
        ELSE.
          APPEND ls_tp_same_object TO ex_older.
        ENDIF.
      ENDIF.
    ENDLOOP.

    SORT ex_newer BY as4date DESCENDING as4time DESCENDING.
    SORT ex_older BY as4date DESCENDING as4time DESCENDING.

  ENDMETHOD.                    "get_tps_for_same_object

  METHOD handle_error.
    DATA: lp_msg TYPE string.
    lp_msg = rf_oref->get_text( ).
    CONCATENATE 'ERROR:'(038) lp_msg INTO lp_msg SEPARATED BY space.
    MESSAGE lp_msg TYPE 'E'.
  ENDMETHOD.                    "handle_error

  METHOD check_colwidth.
    DATA: ls_component TYPE abap_compdescr.
    DATA: lp_as4text   TYPE as4text.
    DATA: lp_len       TYPE i.
    SELECT SINGLE scrtext_s
                  FROM dd04t INTO lp_as4text
                  WHERE rollname   = im_name
                  AND   ddlanguage = sy-langu.
    IF lp_as4text IS INITIAL.
      SELECT SINGLE scrtext_m
                    FROM dd04t INTO lp_as4text
                    WHERE rollname   = im_name
                    AND   ddlanguage = sy-langu.
      IF lp_as4text IS INITIAL.
        SELECT SINGLE scrtext_l
                      FROM dd04t INTO lp_as4text
                      WHERE rollname   = im_name
                      AND   ddlanguage = sy-langu.
      ENDIF.
    ENDIF.
    lp_len = STRLEN( lp_as4text ).
    IF lp_len > im_colwidth.
      re_colwidth = lp_len.
    ELSE.
      re_colwidth = im_colwidth.
    ENDIF.
  ENDMETHOD.                    "check_colwidth

  METHOD remove_tp_in_prd.
    LOOP AT me->main_list TRANSPORTING NO FIELDS WHERE prd = co_okay.
      DELETE me->main_list INDEX sy-tabix.
    ENDLOOP.
  ENDMETHOD.                    "remove_tp_in_prd

  METHOD sort_main_list.
    SORT me->main_list BY as4date   ASCENDING
                          as4time    ASCENDING
                          trkorr     ASCENDING
                          object     ASCENDING
                          obj_name   ASCENDING
                          objkey     ASCENDING
                          keyobject  ASCENDING
                          keyobjname ASCENDING
                          tabkey     ASCENDING.
    DELETE ADJACENT DUPLICATES FROM me->main_list.
  ENDMETHOD.                    "sort_main_list

  METHOD top_of_page.
    DATA: lr_logo             TYPE REF TO cl_salv_form_layout_logo.
    DATA: lp_head             TYPE char50.
    DATA: lp_file_in          TYPE localfile.               "#EC NEEDED
    DATA: lp_file_out         TYPE localfile.
    DATA: lp_records_found(5) TYPE n.
    DATA: lp_picture          TYPE bds_typeid. "VALUE 'XXXXXXXXXXXXXX'.
    DATA: lr_rows             TYPE REF TO cl_salv_form_layout_grid.
    DATA: lr_rows_flow        TYPE REF TO cl_salv_form_layout_flow.
    DATA: lr_row              TYPE REF TO cl_salv_form_layout_flow.
    CREATE OBJECT lr_rows_flow.
    lr_rows = lr_rows_flow->create_grid( ).
    lr_rows->create_grid( row     = 0
                          column  = 0
                          rowspan = 0
                          colspan = 0 ).
*   Header of Top of Page
    lp_head = 'Information'(t05).
    lr_row = lr_rows->add_row( ).
    lr_row->create_header_information(
            text = lp_head
            ).
*   Split filename from path
    IF NOT me->filename IS INITIAL.
      lp_file_out = me->filename.
      DO.
        IF lp_file_out CS '\'.
          SPLIT lp_file_out AT '\' INTO lp_file_in lp_file_out.
        ELSE.
          EXIT.
        ENDIF.
      ENDDO.
      lr_row = lr_rows->add_row( ).
      lr_row = lr_rows->add_row( ).
      lr_row->create_label(
        text    = 'File uploaded:'(049) ).
      lr_row->create_text(
              text      = ' '
              ).
      lr_row->create_text(
        text   = lp_file_out(50)
        ).
    ENDIF.
    lr_row = lr_rows->add_row( ).
    lr_row->create_text(
            text    = 'If there is a warning icon in column `Warning`, ' &
                      'double-clicking on the icon will display a list ' &
                      'of objects that should be checked'(h01)
            ).
    lr_row = lr_rows->add_row( ).
    lr_row->create_text(
            text    = 'You can add these conflicts by means of the ' &
                      'button ''Add Conflicts'' in the application toolbar ' &
                      'or doubleclicking the warning'(h02)
            ).
    lr_row = lr_rows->add_row( ).
    lr_row = lr_rows->add_row( ).
    lr_row->create_label(
            text    = 'No of Records found:'(t04)
            ).
    CASE sy-ucomm.
      WHEN '&PREP_XLS'.
        DESCRIBE TABLE me->main_list_xls LINES lp_records_found.
      WHEN OTHERS.
        DESCRIBE TABLE me->main_list LINES lp_records_found.
    ENDCASE.
    lr_row->create_text(
            text      = ' '
            ).
    lr_row->create_text(
            text      = lp_records_found
            tooltip   = lp_records_found
            ).
*    lr_row = lr_rows->add_row( ).
*   Create logo layout, set grid content on left and logo image on right
    CREATE OBJECT lr_logo.
    lr_logo->set_left_content( lr_rows_flow ).
    lr_logo->set_right_logo( lp_picture ).
    ex_form_element = lr_logo.
  ENDMETHOD.                    "top_of_page

  METHOD version_check.
    DATA: lversno_list      TYPE STANDARD TABLE OF  vrsn,
          version_list      TYPE STANDARD TABLE OF  vrsd,
          ls_version_list  TYPE vrsd,
          lp_destination   TYPE rfcdest.
    FIELD-SYMBOLS: <l_main_list> TYPE ty_request_details.
    DELETE ADJACENT DUPLICATES FROM me->main_list COMPARING object obj_name.
*   Delete tables
    DELETE me->main_list WHERE objfunc = 'K'.
    LOOP AT me->main_list ASSIGNING <l_main_list>.
      REFRESH: lversno_list,
               version_list.
      CLEAR:   ls_version_list.
      ls_version_list-objname = <l_main_list>-obj_name.
      ls_version_list-objtype = <l_main_list>-object.
*     Check local
      CALL FUNCTION 'SVRS_GET_VERSION_DIRECTORY_46'
        EXPORTING
          destination            = 'NONE'
          objname                = ls_version_list-objname
          objtype                = ls_version_list-objtype
        TABLES
          lversno_list           = lversno_list
          version_list           = version_list
        EXCEPTIONS
          no_entry               = 1
          communication_failure_ = 2
          system_failure         = 3
          OTHERS                 = 4.
      FIELD-SYMBOLS <version_list> TYPE vrsd.
      LOOP AT version_list ASSIGNING <version_list>.     "#EC CI_NESTED
        IF <version_list>-versno > ls_version_list-versno.
*       Latest version.
          ls_version_list = <version_list>.
        ENDIF.
      ENDLOOP.
      REFRESH: lversno_list,
               version_list.
      lp_destination = me->qas_system.
*     Check system
      CALL FUNCTION 'SVRS_GET_VERSION_DIRECTORY_46'
        EXPORTING
          destination            = lp_destination
          objname                = ls_version_list-objname
          objtype                = ls_version_list-objtype
        TABLES
          lversno_list           = lversno_list
          version_list           = version_list
        EXCEPTIONS
          no_entry               = 1
          communication_failure_ = 2
          system_failure         = 3
          OTHERS                 = 4.
      IF sy-subrc <> 0.
        APPEND INITIAL LINE TO version_list ASSIGNING <version_list>.
        <l_main_list>-warning_txt = 'No version found to compare'(w02).
      ENDIF.
      LOOP AT version_list ASSIGNING <version_list>.     "#EC CI_NESTED
        IF <version_list>-korrnum <> ls_version_list-korrnum.
          <l_main_list>-warning_lvl  = co_error.
          <l_main_list>-warning_rank = co_error_rank.
        ELSEIF <version_list>-korrnum IS INITIAL.
          <l_main_list>-warning_lvl  = co_warn.
          <l_main_list>-warning_rank = co_warn_rank.
        ELSE.
          <l_main_list>-warning_lvl  = co_okay.
          <l_main_list>-warning_rank = co_okay_rank.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.                    "version_check

  METHOD display_excel.
    DATA: ls_main_list_xls TYPE me->ty_request_details.
    DATA: lt_main_list_xls TYPE me->tt_request_details.
    DATA: lp_variant       TYPE disvariant.
    DATA: lp_return        TYPE c.
    DATA: lp_highest_lvl   TYPE icon_d.
    DATA: lp_highest_rank  TYPE numc4.
    DATA: lp_highest_text  TYPE text74.
    DATA: lp_highest_col   TYPE lvc_t_scol.

    FIELD-SYMBOLS: <l_main_list> TYPE ty_request_details.

*   Only when called from the Main Screen (Object Level). Do not build again
*   when the XLS list has been build already.
    CHECK: me->main_list_xls IS INITIAL.
*   Remove duplicate transport numbers (only need single lines):
    me->main_list_xls[] = im_table[].
    SORT me->main_list_xls BY trkorr ASCENDING.
    DELETE ADJACENT DUPLICATES FROM      me->main_list_xls
                               COMPARING trkorr.
*   Extra actions:
*   - Make sure to keep the highest warning level
*   - rename Icons to text
*   - remove transports not in QAS
    CLEAR: lp_return.
    LOOP AT me->main_list_xls INTO me->main_list_line_xls.
      CLEAR: lp_highest_lvl,
             lp_highest_rank,
             lp_highest_text,
             lp_highest_col.
*     Remove transports not in QAS and transports in prd that do not
*     need to be re-transported:
      IF me->main_list_line_xls-qas <> me->co_okay OR
         me->main_list_line_xls-prd =  me->co_okay.
        lp_return = abap_true.
        LOOP AT me->main_list ASSIGNING <l_main_list>    "#EC CI_NESTED
                              WHERE trkorr = me->main_list_line_xls-trkorr.
          <l_main_list>-warning_lvl  = co_tp_fail.
          <l_main_list>-warning_rank = co_tp_fail_rank.
          <l_main_list>-warning_txt  = lp_fail_text.
        ENDLOOP.
*        EXIT.
      ENDIF.
*     Rename Documentation Icon to text
      IF me->main_list_line_xls-info = me->co_docu.
        me->main_list_line_xls-info = 'Yes'(037).
      ENDIF.
*     Make sure to find and keep the highest warning level for the
*     transport
      LOOP AT me->main_list INTO  main_list_line         "#EC CI_NESTED
                            WHERE trkorr = me->main_list_line_xls-trkorr.
        IF main_list_line-warning_rank > lp_highest_rank.
          lp_highest_rank = main_list_line-warning_rank.
          lp_highest_lvl  = main_list_line-warning_lvl.
          lp_highest_text = main_list_line-warning_txt.
          lp_highest_col  = main_list_line-t_color.
        ENDIF.
      ENDLOOP.
      rf_ztct->refresh_alv( ).                   "Refresh the ALV
*     Add correct warning and change Warning Lvl Icon to text:
      IF sy-subrc = 0.
        me->main_list_line_xls-warning_lvl  = lp_highest_lvl.
        me->main_list_line_xls-warning_rank = lp_highest_rank.
        me->main_list_line_xls-warning_txt  = lp_highest_text.
        me->main_list_line_xls-t_color      = lp_highest_col.
        CASE lp_highest_lvl.
          WHEN me->co_info OR me->co_hint.
            me->main_list_line_xls-warning_lvl = 'Info'(024).
          WHEN me->co_error.
            me->main_list_line_xls-warning_lvl = 'ERR.'(033).
          WHEN me->co_ddic.
            me->main_list_line_xls-warning_lvl = 'ERR.'(033).
          WHEN me->co_warn.
            me->main_list_line_xls-warning_lvl = 'Warn'(034).
          WHEN OTHERS.
            CLEAR: me->main_list_line_xls-warning_lvl.
        ENDCASE.
        IF main_list_line-prd = co_scrap.
          me->main_list_line_xls-re_import = 'Import again'(040).
        ENDIF.
      ENDIF.
*     Apply the changes
      TRY.
          MODIFY me->main_list_xls FROM me->main_list_line_xls.
        CATCH cx_root INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.
    ENDLOOP.
*   Message if entries were deleted because they were not in QAS:
    IF lp_return = abap_true.
      MESSAGE i000(db)
         WITH 'Some transports will be deleted from the list because'(m02)
              'they are missing in Acceptance or are already in'(m03)
              'Production but not marked for re-import.'(m04)
              'Please check the main list.'(m05).
      FREE: rf_table_xls.
      FREE: me->main_list_xls.
      EXIT.
    ENDIF.
*   Display short list for copy to Excel transport list:
    me->alv_xls_init( IMPORTING ex_rf_table = rf_table_xls
                      CHANGING  ch_table = main_list_xls ).
    me->alv_set_properties( EXPORTING im_table = rf_table_xls ).
    me->alv_xls_output( ).
    FREE rf_table_xls.
    REFRESH: main_list_xls.
  ENDMETHOD.                    "display_excel

  METHOD set_properties_conflicts.
    TYPES: BEGIN OF lty_field_ran,
             sign   TYPE c LENGTH 1,
             option TYPE c LENGTH 2,
             low    TYPE fieldname,
             high   TYPE fieldname,
           END OF lty_field_ran.
    DATA: ls_reference      TYPE salv_s_ddic_reference.
    DATA: ls_s_column_ref   TYPE salv_s_column_ref.
    DATA: lr_column_table   TYPE REF TO cl_salv_column_table.
*   Declaration for Aggregate Function Settings
    DATA: lr_aggregations   TYPE REF TO cl_salv_aggregations.
    DATA: ls_table          TYPE me->ty_request_details.
    DATA: lp_popup_width    TYPE lvc_outlen.  "Length
    DATA: lp_cw_columns     TYPE lvc_outlen.  "Length
    DATA: lp_cw_korrnum     TYPE lvc_outlen.  "Length
    DATA: lp_cw_tr_descr    TYPE lvc_outlen.  "Length
    DATA: lp_cw_object      TYPE lvc_outlen.  "Length
    DATA: lp_cw_obj_name    TYPE lvc_outlen.  "Length
    DATA: lp_cw_tabkey      TYPE lvc_outlen.  "Length
    DATA: lp_cw_author      TYPE lvc_outlen.  "Length
    DATA: lp_cw_reimport    TYPE lvc_outlen.  "Length
    DATA: lp_cw_warning_lvl TYPE lvc_outlen.  "Length
    DATA: lp_cw_date        TYPE lvc_outlen.  "Length
    DATA: lp_cw_time        TYPE lvc_outlen.  "Length
    DATA: lp_cw_keyobject   TYPE lvc_outlen.  "Length
    DATA: lp_cw_keyobjname  TYPE lvc_outlen.  "Length
    DATA: lr_table_des      TYPE REF TO cl_abap_structdescr.
    DATA: lr_type_des       TYPE REF TO cl_abap_typedescr.
    DATA: lt_details        TYPE abap_compdescr_tab.
    DATA: ls_details        TYPE abap_compdescr.
    DATA: lp_field          TYPE string.
    DATA: lp_length         TYPE i.
    DATA: lp_data_type      TYPE string.
    DATA: lp_bool           TYPE abap_bool.
*   Declaration for ALV Columns
    DATA: lr_columns_table    TYPE REF TO cl_salv_columns_table.
    DATA: lt_t_column_ref     TYPE salv_t_column_ref.
*   Declaration for Sort Function Settings
    DATA: lr_sorts            TYPE REF TO cl_salv_sorts.
*   Declaration for Table Selection settings
    DATA: lr_selections       TYPE REF TO cl_salv_selections.
*   Declaration for Global Display Settings
    DATA: lr_display_settings TYPE REF TO cl_salv_display_settings.
*   Declarations for Title
    DATA: lp_version          TYPE char10.
    DATA: lp_title            TYPE lvc_title.
    DATA: l_o_tabledescr         TYPE REF TO cl_abap_tabledescr,
          l_o_typedescr          TYPE REF TO cl_abap_typedescr,
          l_o_structdescr        TYPE REF TO cl_abap_structdescr,
          l_s_abap_compdescr_tab TYPE abap_compdescr.
    FIELD-SYMBOLS: <l_type> TYPE ANY.
*   To remove some columns from the output
    DATA: lra_fieldname TYPE RANGE OF lty_field_ran.
    DATA: ls_fieldname  TYPE lty_field_ran.
*   Texts
    DATA: lp_short_text       TYPE char10.
    DATA: lp_medium_text      TYPE char20.
    DATA: lp_long_text        TYPE char40.

*   Individual Column Properties.
*   Build range for all columns to be removed
    ls_fieldname-option = 'EQ'.
    ls_fieldname-sign = 'I'.
    ls_fieldname-low = 'INFO'.
    APPEND ls_fieldname TO lra_fieldname.
*    ls_fieldname-low = 'TR_DESCR'.
*    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'RETCODE'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'TRSTATUS'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'STATUS_TEXT'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'TRFUNCTION'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'TRFUNCTION_TXT'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'OBJKEY'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'OBJFUNC'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'CHECKED_BY'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'PROJECT'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'PROJECT_DESCR'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'WARNING_TXT'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'WARNING_RANK'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'SYSTEMID'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'STEPID'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'DEV'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'QAS'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'PRD'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'FLAG'.
    APPEND ls_fieldname TO lra_fieldname.
    ls_fieldname-low = 'CHECKED'.
    APPEND ls_fieldname TO lra_fieldname.
*   Create the standard output fields.
*   Get the structure of the table.
    lr_table_des ?=
      cl_abap_typedescr=>describe_by_data( me->main_list_line ).
    lt_details[] = lr_table_des->components[].
    LOOP AT lt_details INTO ls_details.
      CONCATENATE 'ME->MAIN_LIST_LINE' '-'
                  ls_details-name INTO lp_field.
      ASSIGN (lp_field) TO <l_type>.
      CHECK <l_type> IS ASSIGNED.
      lr_type_des = cl_abap_typedescr=>describe_by_data( <l_type> ).
      lp_length = STRLEN( lr_type_des->absolute_name ).
      lp_data_type = lr_type_des->absolute_name+6(lp_length).
    ENDLOOP.
*   Determine the number of fields in the structure
    FIELD-SYMBOLS:  <l_fs_field1> TYPE ANY.
    TRY.
        l_o_typedescr = cl_abap_tabledescr=>describe_by_data( p_data = im_table ).
        l_o_tabledescr ?= l_o_typedescr.
        l_o_structdescr ?= l_o_tabledescr->get_table_line_type( ).
      CATCH cx_sy_move_cast_error INTO rf_root.
        rf_ztct->handle_error( EXPORTING rf_oref = rf_root ).
      CATCH cx_root INTO rf_root.
        rf_ztct->handle_error( EXPORTING rf_oref = rf_root ).
    ENDTRY.

*   Determine total width
    LOOP AT im_table INTO ls_table.
      me->determine_col_width( EXPORTING im_field    = ls_table-trkorr
                               CHANGING  ex_colwidth = lp_cw_korrnum ).
      me->determine_col_width( EXPORTING im_field    = ls_table-tr_descr
                               CHANGING  ex_colwidth = lp_cw_tr_descr ).
      me->determine_col_width( EXPORTING im_field    = ls_table-warning_lvl
                               CHANGING  ex_colwidth = lp_cw_warning_lvl ).
      me->determine_col_width( EXPORTING im_field    = ls_table-object
                               CHANGING  ex_colwidth = lp_cw_object ).
      me->determine_col_width( EXPORTING im_field    = ls_table-obj_name
                               CHANGING  ex_colwidth = lp_cw_obj_name ).
*      lp_cw_obj_name = lp_cw_obj_name + 10.
      me->determine_col_width( EXPORTING im_field    = ls_table-tabkey
                               CHANGING  ex_colwidth = lp_cw_tabkey ).
      me->determine_col_width( EXPORTING im_field    = ls_table-keyobject
                               CHANGING  ex_colwidth = lp_cw_keyobject ).
      me->determine_col_width( EXPORTING im_field    = ls_table-keyobjname
                               CHANGING  ex_colwidth = lp_cw_keyobjname ).
      me->determine_col_width( EXPORTING im_field    = ls_table-as4date
                               CHANGING  ex_colwidth = lp_cw_date ).
      me->determine_col_width( EXPORTING im_field    = ls_table-as4time
                               CHANGING  ex_colwidth = lp_cw_time ).
      me->determine_col_width( EXPORTING im_field    = ls_table-as4user
                               CHANGING  ex_colwidth = lp_cw_author ).
      me->determine_col_width( EXPORTING im_field    = ls_table-re_import
                               CHANGING  ex_colwidth = lp_cw_reimport ).
    ENDLOOP.
*   Global Display Settings
    CLEAR: lr_display_settings.
*   Build title:
*   Get version to display in title:
    SELECT datum FROM  vrsd
                 INTO  vrsd-datum UP TO 1 ROWS
                 WHERE objtype = 'REPS'
                 AND   objname = sy-repid.
      WRITE vrsd-datum TO lp_version.
    ENDSELECT.
    IF lp_version IS NOT INITIAL.
      SELECT SINGLE text FROM  d347t INTO lp_title
                         WHERE progname = sy-repid
                         AND   sprsl    = sy-langu
                         AND   obj_code = '001'.
      IF sy-subrc <> 0.
        SELECT SINGLE text FROM  d347t INTO lp_title
                           WHERE progname = sy-repid
                           AND   sprsl    = 'EN'
                           AND   obj_code = '001'.
      ENDIF.
    ENDIF.
*   Set title
    IF lp_title IS INITIAL.
      lp_title = sy-title.
    ELSE.
      REPLACE '&1' WITH lp_version INTO lp_title.
    ENDIF.
*   Global display settings
    lr_display_settings = rf_conflicts->get_display_settings( ).
*   Activate Striped Pattern
    lr_display_settings->set_striped_pattern( if_salv_c_bool_sap=>true ).
*   Report header
    lr_display_settings->set_list_header( lp_title ).
*   Aggregate Function Settings
    lr_aggregations = rf_conflicts->get_aggregations( ).
*   Sort Functions
    lr_sorts = rf_conflicts->get_sorts( ).
    IF lr_sorts IS NOT INITIAL.
      TRY.
          lr_sorts->add_sort( columnname = 'AS4DATE'
                               position = 1
                               sequence   = if_salv_c_sort=>sort_up
                               subtotal   = if_salv_c_bool_sap=>false
                               obligatory = if_salv_c_bool_sap=>false ).
        CATCH cx_salv_not_found INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
        CATCH cx_salv_existing INTO rf_root.
*          me->handle_error( EXPORTING rf_oref = rf_root ).
        CATCH cx_salv_data_error INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.
      TRY.
          lr_sorts->add_sort( columnname = 'AS4TIME'
                               position = 2
                               sequence   = if_salv_c_sort=>sort_up
                               subtotal   = if_salv_c_bool_sap=>false
                               group      = if_salv_c_sort=>group_none
                               obligatory = if_salv_c_bool_sap=>false ).
        CATCH cx_salv_not_found INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
        CATCH cx_salv_existing INTO rf_root.
*          rf_ztct->handle_error( EXPORTING rf_oref = rf_root ).
        CATCH cx_salv_data_error INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.
    ENDIF.
*   Table Selection Settings
    lr_selections = rf_conflicts->get_selections( ).
    IF lr_selections IS NOT INITIAL.
*     Allow row Selection
      lr_selections->set_selection_mode(
                      if_salv_c_selection_mode=>row_column ).
    ENDIF.
*   Event Register settings
    rf_events_table = rf_conflicts->get_event( ).
    CREATE OBJECT rf_handle_events.
    SET HANDLER rf_handle_events->on_function_click     FOR rf_events_table.
    SET HANDLER rf_handle_events->on_double_click_popup FOR rf_events_table.
    SET HANDLER rf_handle_events->on_link_click_popup   FOR rf_events_table.
*   Get the columns from ALV Table
    lr_columns_table = rf_conflicts->get_columns( ).
    IF lr_columns_table IS NOT INITIAL.
      REFRESH : lt_t_column_ref.
      lt_t_column_ref = lr_columns_table->get( ).
*     Get columns properties
      lr_columns_table->set_optimize( if_salv_c_bool_sap=>true ).
      lr_columns_table->set_key_fixation( if_salv_c_bool_sap=>true ).
      TRY.
          lr_columns_table->set_color_column( 'T_COLOR' ).
        CATCH cx_salv_data_error INTO rf_root.
          me->handle_error( EXPORTING rf_oref = rf_root ).
      ENDTRY.

      LOOP AT lt_t_column_ref INTO ls_s_column_ref.
        TRY.
            lr_column_table ?=
              lr_columns_table->get_column( ls_s_column_ref-columnname ).
          CATCH cx_salv_not_found INTO rf_root.
            me->handle_error( EXPORTING rf_oref = rf_root ).
        ENDTRY.
        IF lr_column_table IS NOT INITIAL.
*         Make Mandt column invisible
          IF lr_column_table->get_ddic_datatype( ) = 'CLNT'.
            lr_column_table->set_technical( if_salv_c_bool_sap=>true ).
          ENDIF.
*         Create Aggregate function total for All Numeric/Currency Fields
          IF lr_column_table->get_ddic_inttype( ) EQ 'P' OR
             lr_column_table->get_ddic_datatype( ) EQ 'CURR'.
            IF lr_aggregations IS NOT INITIAL.
              TRY.
                  lr_aggregations->add_aggregation(
                                    columnname = ls_s_column_ref-columnname
                                    aggregation = if_salv_c_aggregation=>total ).
                CATCH cx_salv_data_error INTO rf_root.
                  me->handle_error( EXPORTING rf_oref = rf_root ).
                CATCH cx_salv_not_found INTO rf_root.
                  me->handle_error( EXPORTING rf_oref = rf_root ).
                CATCH cx_salv_existing INTO rf_root.
                  me->handle_error( EXPORTING rf_oref = rf_root ).
              ENDTRY.
            ENDIF.
          ENDIF.
*         Create Check box for fields with domain "XFELD"
          IF lr_column_table->get_ddic_domain( ) EQ 'XFELD'.
            lr_column_table->set_cell_type( if_salv_c_cell_type=>checkbox ).
          ENDIF.
*         Add Hotspot&Hyper Link to the column vbeln
          IF ls_s_column_ref-columnname EQ 'TRKORR'.
            lr_column_table->set_cell_type( if_salv_c_cell_type=>hotspot ).
            lr_column_table->set_key( if_salv_c_bool_sap=>true ).
          ENDIF.
*         Remove columns that are not required
          IF lr_column_table->get_columnname( ) IN lra_fieldname.
            lr_column_table->set_technical( if_salv_c_bool_sap=>true ).
            CONTINUE.
          ENDIF.
          CASE lr_column_table->get_columnname( ).
            WHEN 'TRKORR'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              lp_cw_korrnum = me->check_colwidth( im_name     = 'TRKORR'
                                                  im_colwidth = lp_cw_korrnum ).
              lr_column_table->set_output_length( lp_cw_korrnum ).
            WHEN 'TR_DESCR'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              lp_cw_tr_descr = me->check_colwidth( im_name     = 'TR_DESCR'
                                                   im_colwidth = lp_cw_tr_descr ).
              lr_column_table->set_output_length( lp_cw_tr_descr ).
            WHEN 'WARNING_LVL'.
              IF check_flag = abap_true.
                ls_reference-table = 'FCALV_S_RMLIFO20'.
                ls_reference-field = 'WARNING'.
                lr_column_table->set_ddic_reference( ls_reference ).
                lr_column_table->set_icon( ).
                lr_column_table->set_output_length( lp_cw_warning_lvl ).
              ELSE.
                lr_column_table->set_technical( ).
              ENDIF.
            WHEN 'OBJECT'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              lp_cw_object = me->check_colwidth( im_name     = 'OBJECT'
                                                 im_colwidth = lp_cw_object ).
              lr_column_table->set_output_length( lp_cw_object ).
            WHEN 'OBJ_NAME'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              lp_cw_obj_name = me->check_colwidth( im_name     = 'OBJ_NAME'
                                                   im_colwidth = lp_cw_obj_name ).
              lr_column_table->set_output_length( lp_cw_obj_name ).
            WHEN 'TABKEY'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              IF lp_cw_tabkey IS INITIAL.
                lr_column_table->set_technical( ).
              ELSE.
                lp_cw_tabkey = me->check_colwidth( im_name     = 'TABKEY'
                                                   im_colwidth = lp_cw_tabkey ).
                lr_column_table->set_output_length( lp_cw_tabkey ).
              ENDIF.
            WHEN 'KEYOBJECT'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              IF lp_cw_keyobject IS INITIAL.
                lr_column_table->set_technical( ).
              ELSE.
                lp_cw_keyobject = me->check_colwidth( im_name     = 'KEYOBJECT'
                                                      im_colwidth = lp_cw_keyobject ).
                lr_column_table->set_output_length( lp_cw_keyobject ).
              ENDIF.
            WHEN 'KEYOBJNAME'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              IF lp_cw_keyobjname IS INITIAL.
                lr_column_table->set_technical( ).
              ELSE.
                lp_cw_keyobjname = me->check_colwidth( im_name     = 'KEYOBJNAME'
                                                       im_colwidth = lp_cw_keyobjname ).
                lr_column_table->set_output_length( lp_cw_keyobjname ).
              ENDIF.
            WHEN 'AS4DATE'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              lp_cw_date = me->check_colwidth( im_name     = 'AS4DATE'
                                               im_colwidth = lp_cw_date ).
              lr_column_table->set_output_length( lp_cw_date ).
            WHEN 'AS4TIME'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              lp_cw_time = me->check_colwidth( im_name     = 'AS4TIME'
                                               im_colwidth = lp_cw_time ).
              lr_column_table->set_output_length( lp_cw_time ).
            WHEN 'AS4USER'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              lp_cw_author = me->check_colwidth( im_name     = 'AS4USER'
                                                 im_colwidth = lp_cw_author ).
              lr_column_table->set_output_length( lp_cw_author ).
            WHEN 'RE_IMPORT'.
              lr_column_table->set_key( if_salv_c_bool_sap=>false ).
              lp_short_text = 'Re-import'(044).
              lp_long_text = lp_medium_text = 'Import again'(045).
              lr_column_table->set_short_text( lp_short_text ).
              lr_column_table->set_medium_text( lp_medium_text ).
              lr_column_table->set_long_text( lp_long_text ).
              lp_cw_reimport = me->check_colwidth( im_name     = 'RE_IMPORT'
                                                   im_colwidth = lp_cw_reimport ).
              lr_column_table->set_output_length( lp_cw_reimport ).
          ENDCASE.
*         Count the number of columns that are visible
          lp_bool = lr_column_table->is_technical( ).
          IF lp_bool = abap_false.
            lp_cw_columns = lp_cw_columns + 1.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    ex_xend = lp_cw_korrnum     + lp_cw_tr_descr   +
              lp_cw_warning_lvl + lp_cw_object     +
              lp_cw_obj_name    + lp_cw_tabkey     +
              lp_cw_keyobject   + lp_cw_keyobjname +
              lp_cw_date        + lp_cw_time       +
              lp_cw_author      + lp_cw_reimport   +
              lp_cw_columns.
  ENDMETHOD.                    "set_properties_conflicts

  METHOD prepare_ddic_check.
    me->set_ddic_objects( ).
    me->set_where_used( ).
  ENDMETHOD.                    "prepare_ddic_check

  METHOD set_ddic_objects.
    REFRESH: ddic_objects.
*   DD01L (Domains)
    SELECT a~domname  APPENDING TABLE ddic_objects
           FROM dd01l AS a INNER JOIN tadir AS b
           ON a~domname = b~obj_name
           WHERE b~devclass LIKE 'Z%'.
*   DD02L (SAP-tables)
    SELECT a~tabname  APPENDING TABLE ddic_objects
           FROM dd02l AS a INNER JOIN tadir AS b
           ON a~tabname = b~obj_name
           WHERE b~devclass LIKE 'Z%'.
*   DD04L (Data elements)
    SELECT a~rollname  APPENDING TABLE ddic_objects
           FROM dd04l AS a INNER JOIN tadir AS b
           ON a~rollname = b~obj_name
           WHERE b~devclass LIKE 'Z%'.

    SORT ddic_objects.
    DELETE ADJACENT DUPLICATES FROM ddic_objects.
  ENDMETHOD.   "set_ddic_objects

  METHOD do_ddic_check.
    DATA: ls_ddic_conflict_info TYPE ty_request_details.
    DATA: ls_main              TYPE ty_request_details.
    DATA: lp_obj_name          TYPE trobj_name.
*  Check if the object exists in the where_used list for data
*  dictionary elements that do not yet exist in production.
*  If it is found in the where_used list, then the object MUST
*  also be in the main transport list. If it is not, it is an ERROR,
*  because transporting to production will cause DUMPS.
*  Check is independent of Flags. (Re)Check all objects in the list!
*  Message: "Contains an object that does not exist in prod. and
*            is not in the list"
    LOOP AT ch_main_list INTO ls_main.
      LOOP AT where_used INTO  where_used_line
                         WHERE object = ls_main-obj_name. "#EC CI_NESTED
*       If the used object (i.e. element, domain etc) is in the DDIC_E071 list,
*       it means that the used object is NOT in production yet. Transporting
*       the object that uses this used object will cause dumps in production.
        READ TABLE ddic_e071 INTO ddic_e071_line
                             WITH KEY obj_name = where_used_line-used_obj.
*       The object in this transport contains a DDIC object that is not yet in
*       Production. This will cause dumps, unless the DDIC object can be found
*       as an object in the transport list!
        IF sy-subrc = 0.
*         Check if the used object can be found in the main list
          READ TABLE ch_main_list WITH KEY obj_name = where_used_line-used_obj
                                  TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            IF ls_main-flag = abap_true.
              lp_obj_name = where_used_line-used_obj.
              ls_ddic_conflict_info = me->get_tp_info( im_trkorr   = ddic_e071_line-trkorr
                                                       im_obj_name = lp_obj_name ).
              MOVE-CORRESPONDING ls_ddic_conflict_info TO me->conflict_line.
              me->conflict_line-warning_lvl  = co_ddic.
              me->conflict_line-warning_rank = co_ddic_rank.
              me->conflict_line-warning_txt  = lp_ddic_text.
              APPEND: me->conflict_line TO me->conflicts.
              CLEAR:  me->conflict_line.
            ENDIF.
            ls_main-warning_lvl  = co_ddic.
            ls_main-warning_rank = co_ddic_rank.
            ls_main-warning_txt  = lp_ddic_text.
            MODIFY: ch_main_list FROM ls_main TRANSPORTING warning_lvl
                                                           warning_rank
                                                           warning_txt
                                                           t_color.
            me->total = me->total + 1.
          ELSE.
            IF ls_main-warning_rank = co_ddic_rank.
              ls_main-flag         = abap_true.
              MODIFY: ch_main_list FROM ls_main TRANSPORTING flag.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.                    "do_ddic_check

  METHOD set_where_used.
    DATA: ta_stms_wbo_requests TYPE TABLE OF stms_wbo_request,
          st_stms_wbo_requests TYPE stms_wbo_request.
    DATA: st_systems           TYPE ctslg_system.
    DATA: lp_scope             TYPE seu_obj.
    DATA: lp_answer            TYPE char1.
    DATA: lt_trkorrs           TYPE trkorrs.
    DATA: lp_ddic_object       TYPE string.
    DATA: ls_ddic_object       TYPE string.
    DATA: lp_index             TYPE syindex.
    DATA: lp_counter           TYPE i.
    DATA: lp_total(10)         TYPE n.
    DATA: lp_deleted           TYPE abap_bool.
    DATA: lp_obj_name          TYPE trobj_name.

    REFRESH: ddic_e071.
* Get all object types
*--select values for pgmid/object/text from database--------------------
    DATA: lt_object_table  TYPE tr_object_texts.
    DATA: ls_object        TYPE ko100.
    DATA: lt_objrangtab    TYPE objrangtab.
    DATA: ls_objtyprang    TYPE objtyprang.
    DATA: lt_objtype       TYPE TABLE OF versobjtyp.
    DATA: ls_objtype       TYPE versobjtyp.
    DATA: lp_chars         TYPE string VALUE '1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ'.

* Get all object types that have been transported before
    SELECT DISTINCT object FROM e071 INTO TABLE lt_objtype.
    ls_objtyprang-sign   = 'I'.
    ls_objtyprang-option = 'EQ'.
    LOOP AT lt_objtype INTO ls_objtyprang-low.
      IF ls_objtyprang-low CN lp_chars.
        CONTINUE.
      ENDIF.
      APPEND ls_objtyprang TO lt_objrangtab.
    ENDLOOP.

* Now find ALL transports for the DDIC objects with Program ID R3TR,
* for the object types found
    CLEAR: lp_counter.
    DESCRIBE TABLE ddic_objects LINES lp_total.
    LOOP AT ddic_objects INTO ls_ddic_object.
      lp_counter = lp_counter + 1.
      lp_obj_name = ls_ddic_object.
      me->progress_indicator( EXPORTING im_counter = lp_counter
                                        im_object  = lp_obj_name
                                        im_total   = lp_total
                                        im_text    = 'Collecting DDIC transports'(053)
                                        im_flag    = ' ' ).
      SELECT trkorr pgmid object obj_name
             FROM e071 APPENDING CORRESPONDING FIELDS OF TABLE ddic_e071
             WHERE   pgmid    = 'R3TR'
             AND     object   IN lt_objrangtab
             AND     obj_name = ls_ddic_object.      "#EC CI_SEL_NESTED
    ENDLOOP.

*   Check if the transport is in production, if it is, then the
*   DDIC object is existing and 'should' not cause problems.
    CLEAR: lp_counter.
    LOOP AT ddic_e071 INTO ddic_e071_line.
      lp_index = sy-tabix.
      lp_deleted = abap_false.
      IF ddic_e071_line-trkorr(3) NS me->dev_system.
*       Not a Development transport, check not required
        DELETE ddic_e071 INDEX lp_index.
        CONTINUE.
      ENDIF.
      REFRESH: ta_stms_wbo_requests.
      CLEAR:   ta_stms_wbo_requests.
      READ TABLE tms_mgr_buffer INTO tms_mgr_buffer_line
                      WITH TABLE KEY request          = ddic_e071_line-trkorr
                                     target_system    = me->dev_system.
      IF sy-subrc = 0.
        ta_stms_wbo_requests = tms_mgr_buffer_line-request_infos.
      ELSE.
        CALL FUNCTION 'TMS_MGR_READ_TRANSPORT_REQUEST'
          EXPORTING
            iv_request                 = ddic_e071_line-trkorr
            iv_target_system           = me->dev_system
            iv_header_only             = 'X'
            iv_monitor                 = ' '
          IMPORTING
            et_request_infos           = ta_stms_wbo_requests
          EXCEPTIONS
            read_config_failed         = 1
            table_of_requests_is_empty = 2
            system_not_available       = 3
            OTHERS                     = 4.
        IF sy-subrc <> 0.
          MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
                  WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
        ELSE.
          tms_mgr_buffer_line-request       = ddic_e071_line-trkorr.
          tms_mgr_buffer_line-target_system = me->dev_system.
          tms_mgr_buffer_line-request_infos = ta_stms_wbo_requests.
          INSERT tms_mgr_buffer_line INTO TABLE tms_mgr_buffer.
        ENDIF.
      ENDIF.
      READ TABLE ta_stms_wbo_requests INDEX 1
                                      INTO st_stms_wbo_requests.
      IF st_stms_wbo_requests-e070-trstatus NA 'NR'.
*       Transport not released, check not required
        DELETE ddic_e071 INDEX lp_index.
        lp_deleted = abap_true.
      ELSEIF st_stms_wbo_requests-e070-trstatus = 'O'.
      ELSE.
*       Retrieve the environments where the transport can be found.
*       Read the info of the request (transport log) to determine the
*       highest environment the transport has been moved to.
        CALL FUNCTION 'TR_READ_GLOBAL_INFO_OF_REQUEST'
          EXPORTING
            iv_trkorr = ddic_e071_line-trkorr
          IMPORTING
            es_cofile = st_request-cofile.
        IF st_request-cofile-systems IS INITIAL.
*         Transport log does not exist: not released or log deleted
          DELETE ddic_e071 INDEX lp_index.
          lp_deleted = abap_true.
        ELSE.
*         Now check in which environments the transport can be found
          LOOP AT st_request-cofile-systems INTO st_systems. "#EC CI_NESTED
*           For each environment, set the status icon:
            CASE st_systems-systemid.
              WHEN me->prd_system.
                DESCRIBE TABLE st_systems-steps LINES tp_lines.
                READ TABLE st_systems-steps INTO st_steps
                                            INDEX tp_lines.
                CHECK st_steps-stepid <> '<'.
*               Transported to production, check not required on this
*               object. Delete all records for this object (not only
*               for this transport but for all transports)
                DELETE ddic_e071 INDEX lp_index.
                lp_deleted = abap_true.
              WHEN OTHERS.
            ENDCASE.
          ENDLOOP.
        ENDIF.
      ENDIF.
*     Show the progress indicator
      IF lp_deleted = abap_false.
*       Only add counter if the line was not deleted...
        lp_counter = lp_counter + 1.
      ENDIF.
      DESCRIBE TABLE ddic_e071 LINES lp_total.
      me->progress_indicator( EXPORTING im_counter = lp_counter
                                        im_object  = ddic_e071_line-obj_name
                                        im_total   = lp_total
                                        im_text    = 'DDIC not transported...'(051)
                                        im_flag    = ' ' ).
    ENDLOOP.
*   Rebuild ddic_objects list
    REFRESH: ddic_objects.
    LOOP AT ddic_e071 INTO ddic_e071_line.
      APPEND ddic_e071_line-obj_name TO ddic_objects.
    ENDLOOP.
    SORT ddic_objects.
    DELETE ADJACENT DUPLICATES FROM ddic_objects.
*   Show the progress indicator
    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        text = 'Retrieving Where Used list'(052).
* Build the WHERE_USED list for all remaining objects
    DATA: ls_objects     TYPE string.
    DATA: where_used_sub TYPE sci_findlst.
    REFRESH: where_used.
    LOOP AT ddic_objects INTO ls_objects.
      REFRESH: ddic_objects_sub.
      APPEND ls_objects TO ddic_objects_sub.
      CALL FUNCTION 'RS_EU_CROSSREF'
        EXPORTING
          i_find_obj_cls           = 'DE' "Data element
          no_dialog                = 'X'
        IMPORTING
          o_scope_obj_cls          = lp_scope
          o_answer                 = lp_answer
        TABLES
          i_findstrings            = ddic_objects_sub
          o_founds                 = where_used_sub
        EXCEPTIONS
          not_executed             = 0
          not_found                = 0
          illegal_object           = 0
          no_cross_for_this_object = 0
          batch                    = 0
          batchjob_error           = 0
          wrong_type               = 0
          object_not_exist         = 0
          OTHERS                   = 0.
      APPEND LINES OF where_used_sub TO where_used.
      REFRESH: where_used_sub.
    ENDLOOP.
* Remove all entries from the where used list that are not existing
* in tables DD01L, DD02L or DD04L
    DATA: lp_string TYPE string.
    LOOP AT where_used INTO where_used_line.
* DD01L (Domains)
      SELECT SINGLE domname
                    FROM dd01l INTO lp_string
                    WHERE domname = where_used_line-used_obj. "#EC CI_SEL_NESTED
      IF sy-subrc <> 0.
* DD02L (SAP-tables)
        SELECT SINGLE tabname
                      FROM dd02l INTO lp_string
                      WHERE tabname = where_used_line-used_obj. "#EC CI_SEL_NESTED
        IF sy-subrc <> 0.
* DD04L (Data elements)
          SELECT SINGLE rollname
                        FROM dd04l INTO lp_string
                        WHERE rollname = where_used_line-used_obj. "#EC CI_SEL_NESTED
        ENDIF.
      ENDIF.
      IF sy-subrc <> 0.
        DELETE where_used INDEX sy-tabix.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.                    "set_where_used

  METHOD get_import_datetime_qas.
    DATA: ta_stms_wbo_requests TYPE TABLE OF stms_wbo_request,
          st_stms_wbo_requests TYPE stms_wbo_request.
    DATA: st_systems           TYPE ctslg_system.
*   Get the last date the object was imported
    CALL FUNCTION 'TR_READ_GLOBAL_INFO_OF_REQUEST'
      EXPORTING
        iv_trkorr = im_trkorr
      IMPORTING
        es_cofile = st_request-cofile.
    LOOP AT st_request-cofile-systems INTO  st_systems
                                      WHERE systemid = me->qas_system.
*               Get the latest import date:
      DESCRIBE TABLE st_systems-steps LINES tp_lines.
      READ TABLE st_systems-steps INTO st_steps
                                  INDEX tp_lines.
      DESCRIBE TABLE st_steps-actions LINES tp_lines.
      READ TABLE st_steps-actions INTO st_actions
                                  INDEX tp_lines.
      MOVE st_actions-time TO ex_as4time.
      MOVE st_actions-date TO ex_as4date.
    ENDLOOP.
    ex_return = sy-subrc.
  ENDMETHOD.                    "get_import_datetime_qas

  METHOD go_back_months.
    DATA: BEGIN OF dat,
            jjjj(4) ,
            mm(2) ,
            tt(2) ,
          END OF dat,

          BEGIN OF hdat,
            jjjj(4) ,
            mm(2) ,
            tt(2) ,
          END OF hdat,
          newmm TYPE p,
          diffjjjj TYPE p.

    WRITE:  im_currdate+0(4) TO dat-jjjj,
            im_currdate+4(2) TO  dat-mm,
            im_currdate+6(2) TO  dat-tt.
    diffjjjj =   ( dat-mm + ( - im_backmonths ) - 1 ) DIV 12.
    newmm    =   ( dat-mm + ( - im_backmonths ) - 1 ) MOD 12 + 1.
    dat-jjjj = dat-jjjj +  diffjjjj.

    IF newmm < 10.
      WRITE '0' TO  dat-mm+0(1).
      WRITE newmm TO  dat-mm+1(1).
    ELSE.
      WRITE newmm TO  dat-mm.
    ENDIF.
    IF dat-tt > '28'.
      hdat-tt = '01'.
      newmm   = ( dat-mm  )  MOD 12 + 1.
      hdat-jjjj = dat-jjjj + ( (  dat-mm ) DIV 12 ).

      IF newmm < 10.
        WRITE '0' TO hdat-mm+0(1).
        WRITE newmm TO hdat-mm+1(1).
      ELSE.
        WRITE newmm TO hdat-mm.
      ENDIF.

      IF dat-tt = '31'.
        re_date = hdat.
        re_date = re_date - 1.
      ELSE.
        IF dat-mm = '02'.
          re_date = hdat.
          re_date = re_date - 1.
        ELSE.
          re_date = dat.
        ENDIF.
      ENDIF.
    ELSE.
      re_date = dat.
    ENDIF.
  ENDMETHOD.                    "go_back_months

ENDCLASS.                    "lcl_ztct IMPLEMENTATION

*--------------------------------------------------------------------*
*       DATA SELECT
*--------------------------------------------------------------------*
START-OF-SELECTION.

  IF rf_ztct IS NOT BOUND.
    TRY .
        CREATE OBJECT rf_ztct.
      CATCH cx_root INTO rf_root.
        tp_msg = rf_root->get_text( ).
        CONCATENATE 'ERROR:'(038) tp_msg INTO tp_msg SEPARATED BY space.
        MESSAGE tp_msg TYPE 'E'.
    ENDTRY.
  ENDIF.

  tp_prefix = rf_ztct->get_tp_prefix( im_dev = pa_dev ).

  IF pa_sel = abap_true.
    tp_process_type = 1.
  ELSE.
    tp_process_type = 3.
  ENDIF.

  IF tp_process_type = 1.
*   Get transports
    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        text = 'Selecting data...'(014).
*   Join over E070, E071:
*   Description is read later to prevent complicated join and
*   increased runtime
    st_trkorr_range-sign   = 'I'.
    st_trkorr_range-option = 'EQ'.
    SELECT a~trkorr
           INTO st_trkorr_range-low
           FROM  e070 AS a JOIN e071 AS b
             ON  a~trkorr = b~trkorr
           WHERE a~trkorr     IN so_korr
           AND   a~as4user    IN so_user
           AND   a~as4date    IN so_date
           AND   b~obj_name   IN so_exobj
           AND   strkorr      = ''
           AND   a~trkorr     LIKE tp_prefix
           AND   a~trkorr     IN ra_project_trkorrs
           AND   ( pgmid = 'LIMU' OR
                   pgmid = 'R3TR' ).
      APPEND st_trkorr_range TO ta_trkorr_range.
    ENDSELECT.
*   Read transport description:
    IF ta_trkorr_range[] IS NOT INITIAL.
      LOOP AT ta_trkorr_range INTO st_trkorr_range.
*       Check if the description contains the search string
        SELECT SINGLE as4text
                      FROM e07t INTO tp_transport_descr
                      WHERE  trkorr = st_trkorr_range-low
                      AND    langu  = sy-langu.      "#EC CI_SEL_NESTED
        IF pa_str CS '*'.
          IF tp_transport_descr NP pa_str.
            DELETE ta_trkorr_range INDEX sy-tabix.
            CONTINUE.
          ENDIF.
        ELSE.
          IF tp_transport_descr NS pa_str.
            DELETE ta_trkorr_range INDEX sy-tabix.
            CONTINUE.
          ENDIF.
        ENDIF.
*       Check if the project is in the selection range
        SELECT reference
               FROM e070a
               UP TO 1 ROWS
               INTO  tp_project_reference
               WHERE trkorr = st_trkorr_range-low
               AND   attribute = 'SAP_CTS_PROJECT'.  "#EC CI_SEL_NESTED
          IF NOT tp_project_reference IN so_proj.
            DELETE ta_trkorr_range INDEX sy-tabix.
          ENDIF.
        ENDSELECT.
      ENDLOOP.
      SORT ta_trkorr_range.
      DELETE ADJACENT DUPLICATES FROM ta_trkorr_range.
    ENDIF.
  ENDIF.

  ta_project_range[]    = so_proj[].
  ta_excluded_objects[] = so_exobj[].
  ta_date_range[]       = so_date[].

END-OF-SELECTION.

*--------------------------------------------------------------------*
*       Main program
*--------------------------------------------------------------------*
  IF ta_trkorr_range IS INITIAL AND
     tp_process_type = 1.
    MESSAGE i000(db) DISPLAY LIKE 'E'
                     WITH 'No transports found...'(m13).
  ELSE.
    PERFORM init_ztct.
    rf_ztct->execute( ).
  ENDIF.

*&---------------------------------------------------------------------*
*&      Form  INIT_ZTCT
*&---------------------------------------------------------------------*
FORM init_ztct.
  rf_ztct->set_check_flag( pa_check ).
  rf_ztct->set_check_tabkeys( pa_chkky ).
  rf_ztct->set_clear_checked( pa_chd ).
  rf_ztct->set_skip_buffer_chk( pa_buff ).
  rf_ztct->set_skiplive( pa_noprd ).
  rf_ztct->set_user_layout( pa_user ).
  rf_ztct->set_trkorr_range( ta_trkorr_range ).
  rf_ztct->set_project_range( ta_project_range ).
  rf_ztct->set_date_range( ta_date_range ).
  rf_ztct->set_excluded_objects( ta_excluded_objects ).
  rf_ztct->set_search_string( pa_str ).
  rf_ztct->set_process_type( tp_process_type ).
  rf_ztct->set_filename( pa_file ).
  rf_ztct->set_systems( EXPORTING im_dev_system = pa_dev
                                  im_qas_system = pa_qas
                                  im_prd_system = pa_prd ).
ENDFORM.                    " INIT_ZTCT
