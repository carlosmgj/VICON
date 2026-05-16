/*
 @licstart  The following is the entire license notice for the JavaScript code in this file.

 The MIT License (MIT)

 Copyright (C) 1997-2020 by Dimitri van Heesch

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software
 and associated documentation files (the "Software"), to deal in the Software without restriction,
 including without limitation the rights to use, copy, modify, merge, publish, distribute,
 sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or
 substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
 BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 @licend  The above is the entire license notice for the JavaScript code in this file
*/
var NAVTREE =
[
  [ "VICON", "index.html", [
    [ "MAIN PAGE", "index.html", "index" ],
    [ "GHDL", "page__g_h_d_l.html", null ],
    [ "GIT REPOSITORY", "page_git.html", [
      [ "GIT FLOW", "page_git.html#sec_gitflow", null ]
    ] ],
    [ "HARDWARE", "page_hardware.html", null ],
    [ "DESIGN HIERARCHY", "page_hierarchy.html", null ],
    [ "REPORTS", "page_reports.html", [
      [ "GHDL — ❌ 1 errors, 2 warnings", "page_reports.html#sec_report_ghdl", [
        [ "TOP.vhd (0 errors, 1 warnings)", "page_reports.html#sec_ghdl_TOP_vhd", null ],
        [ "testbench.vhd (1 errors, 1 warnings)", "page_reports.html#sec_ghdl_testbench_vhd", null ]
      ] ],
      [ "VSG — ❌ 232 errors, 0 warnings", "page_reports.html#sec_report_vsg", [
        [ "TOP.vhd (20 errors, 0 warnings)", "page_reports.html#sec_vsg_TOP_vhd", null ],
        [ "clock_generator.vhd (9 errors, 0 warnings)", "page_reports.html#sec_vsg_clock_generator_vhd", null ],
        [ "i2c_controller.vhd (86 errors, 0 warnings)", "page_reports.html#sec_vsg_i2c_controller_vhd", null ],
        [ "mt9v111.vhd (68 errors, 0 warnings)", "page_reports.html#sec_vsg_mt9v111_vhd", null ],
        [ "sim_utils_pkg.vhd (29 errors, 0 warnings)", "page_reports.html#sec_vsg_sim_utils_pkg_vhd", null ],
        [ "testbench.vhd (20 errors, 0 warnings)", "page_reports.html#sec_vsg_testbench_vhd", null ]
      ] ]
    ] ],
    [ "SETUP", "page_setup.html", [
      [ "AUTO SETUP", "page_setup.html#sec_setup_autosetup", null ],
      [ "PYTHON", "page_setup.html#sec_setup_python", null ],
      [ "JAVA", "page_setup.html#sec_setup_java", null ],
      [ "GHDL", "page_setup.html#sec_setup_ghdl", [
        [ "Binario GHDL", "page_setup.html#subsec_ghdl_binario", null ],
        [ "pyGHDL (bindings Python)", "page_setup.html#subsec_ghdl_pyghdl", null ]
      ] ],
      [ "VUNIT", "page_setup.html#sec_setup_vunit", null ],
      [ "DOXYGEN", "page_setup.html#sec_setup_doxygen", [
        [ "Graphviz", "page_setup.html#subsec_doxygen_graphviz", null ],
        [ "PlantUML", "page_setup.html#subsec_doxygen_plantuml", null ],
        [ "WaveDrom (offline)", "page_setup.html#subsec_doxygen_wavedrom", null ]
      ] ],
      [ "SCRIPT DE DOCUMENTACIÓN VHDL", "page_setup.html#sec_setup_filter", [
        [ "Qué hace", "page_setup.html#subsec_filter_que_hace", null ],
        [ "Convención de comentarios en el .vhd", "page_setup.html#subsec_filter_convencion", null ],
        [ "Configuración en el Doxyfile", "page_setup.html#subsec_filter_doxyfile", null ],
        [ "Verificar el script manualmente", "page_setup.html#subsec_filter_test", null ]
      ] ],
      [ "LATEX", "page_setup.html#sec_setup_latex", null ],
      [ "TEROSHDL", "page_setup.html#sec_setup_teroshdl", [
        [ "TEROSHDL CLI", "page_setup.html#subsec_teroshdl_cli", null ],
        [ "WaveDrom CLI", "page_setup.html#subsec_wavedromcli", null ]
      ] ],
      [ "VGS", "page_setup.html#sec_vgs", null ],
      [ "YOSYS", "page_setup.html#sec_yosys", null ]
    ] ],
    [ "TEAM", "page_team.html", null ],
    [ "TEROSHDL", "page_teroshdldoc.html", null ],
    [ "TEST PAGE", "page_test.html", [
      [ "Lorem Ipsum", "page_test.html#sec_loremipsum", [
        [ "NAVIGABLE DIAGRAM", "page_test.html#subsec_diagram", null ],
        [ "GENERATED WAVEFORM", "page_test.html#subsec_waveform", null ]
      ] ]
    ] ],
    [ "WORK METHODOLOGY", "page_workmethodology.html", [
      [ "AUTODOCUMENTATION", "page_workmethodology.html#sec_comments", [
        [ "WAVEFORMS", "page_workmethodology.html#subsec_comments_wavedrom", null ],
        [ "DRAW IO", "page_workmethodology.html#subsec_drawio", null ]
      ] ],
      [ "Tools", "page_workmethodology.html#sec_work_tools", [
        [ "IDE", "page_workmethodology.html#subsec_ide", [
          [ "VSCODE", "page_workmethodology.html#subsec_vscode", null ]
        ] ]
      ] ]
    ] ],
    [ "Todo List", "todo.html", null ],
    [ "Packages", "namespaces.html", [
      [ "Package List", "namespaces.html", "namespaces_dup" ],
      [ "Package Members", "namespacemembers.html", [
        [ "All", "namespacemembers.html", null ],
        [ "Functions/Procedures/Processes", "namespacemembers_func.html", null ]
      ] ]
    ] ],
    [ "Design Units", "annotated.html", [
      [ "Design Unit List", "annotated.html", "annotated_dup" ],
      [ "Design Unit Index", "classes.html", null ],
      [ "Design Unit Members", "functions.html", [
        [ "All", "functions.html", null ],
        [ "Functions/Procedures/Processes", "functions_func.html", null ],
        [ "Variables", "functions_vars.html", null ]
      ] ]
    ] ],
    [ "Files", "files.html", [
      [ "File List", "files.html", "files_dup" ],
      [ "File Members", "globals.html", [
        [ "All", "globals.html", null ],
        [ "Variables", "globals_vars.html", null ]
      ] ]
    ] ]
  ] ]
];

var NAVTREEINDEX =
[
"_basys3___g_p_i_o_8xdc.html"
];

var SYNCONMSG = 'click to disable panel synchronisation';
var SYNCOFFMSG = 'click to enable panel synchronisation';