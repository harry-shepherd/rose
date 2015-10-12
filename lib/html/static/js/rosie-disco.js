/******************************************************************************
 * (C) British crown copyright 2012-5 Met Office.
 *
 * This file is part of Rose, a framework for scientific suites.
 *
 * Rose is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Rose is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Rose. If not, see <http://www.gnu.org/licenses/>.
 *
 ******************************************************************************/
var Rosie = {};
Rosie.cookie_get = function(name) {
    var cookies = document.cookie.split("; ");
    var value = null;
    $.each(cookies, function(i, item) {
        var pair = item.split("=");
        if (pair[0] == name) {
            value = unescape(pair[1]);
            return false;
        }
    });
    return value;
};
Rosie.cookie_set = function(name, value) {
    document.cookie = name + "=" + escape(value);
};
Rosie.query = function() {
    var q = "";
    var q_ubound = 0;
    var q_open_groups = 0;
    $("#query-table > tbody > tr").each(function(i) {
        if (i > q_ubound) {
            q_ubound = i;
        }
        var row = $(this);
        var conjunction = $(".q_conjunction", row).val();
        var group0 = $(".q_group0", row).val();
        var key = $(".q_key", row).val();
        var operator = $(".q_operator", row).val();
        var value = encodeURIComponent($(".q_value", row).val());
        var group1 = $(".q_group1", row).val();
        if (i != 0) {
            q += "&";
        }
        var filter_list = [conjunction, key, operator, value];
        if (group0) {
            filter_list.splice(1, 0, group0);
            q_open_groups += group0.length
        }
        if (group1) {
            filter_list.push(group1);
            q_open_groups -= group1.length
        }
        q += "q=" + filter_list.join("+");
        var suffix = row.attr("id").substr(1);
    });
    if ($("#query-all").attr("checked")) {
        q += "&all_revs=1"
    }
    if (q_open_groups != 0) {
        alert("Parenthesis error");
        return
    }
    location = "query?" + q;
};
Rosie.query_add = function() {
    var tbody = $("#query-table tbody");
    var rows = $("> tr", tbody);
    var row = rows.last().clone().appendTo(tbody);
    var index = (Number(rows.last().attr("id").substr(2)) + 1).toString();
    row.attr("id", "q_" + index);

    $("select, input", row).each(function() {
        $(this).attr("name", $(this).attr("class") + "_" + index);
    });

    $("select, button", row).removeAttr("disabled");
    $("button", row).click(Rosie.query_remove);
};
Rosie.query_remove = function() {
    $(this).closest("tr").remove();
    var rows = $("#query-table > tbody > tr");
    $(".q_conjunction", rows.first()).attr("disabled", "disabled");
    if (rows.length == 1) {
        rows.first().find("button").prop("disabled", "disabled");
    }
};
Rosie.query_groups_toggle = function () {
    var tbody = $("#query-table tbody");
    var show_groups = $("#show-groups").is(":checked");
    $("#query-table > tbody > tr").each(function(i) {
        var row = $(this);
        var group0 = $(".q_group0", row);
        var group1 = $(".q_group1", row);
        if (show_groups) {
            group0.show();
            group1.show();
        }
        else {
            group0.hide();
            group1.hide();
        }
        if (!show_groups && (group0.val() || group1.val())) {
            $("#show-groups").attr("checked", "checked");
            return Rosie.query_groups_toggle()
        }
    });
};
Rosie.show = function(method) {
    $("#" + method).show();
    $("form[id!=" + method + "]").hide()
};
unix_to_local_date = function(timestamp) {
    return new Date(timestamp).toLocaleString();
};
$(function() {
    var table = $("#list-result-table");
    var hidden_indicies = [];
    var time_indicies = [];
    var ok_cols = ["?", "id", "branch", "revision", "owner", "project", "title"];
    $("#list-result-table thead th").each(function(i) {
        var title = $(this).text();
        if (ok_cols.indexOf(title) == -1) {
            hidden_indicies.push(i);
        }
        if (title == "date") {
            time_indicies.push(i);
        }
    });
    table.dataTable({
        "aaSorting": [[3, "desc"]],
        "aoColumnDefs": [{"bVisible": false, "aTargets": hidden_indicies},
                         {"fnRender": function( o, val )
                              {
                                  var timestamp = o.aData[o.iDataColumn]*1000;
                                  return new Date(timestamp).toLocaleString();
                              },
                          "bUseRendered": false,
                          "aTargets": time_indicies
                         }
                        ],
        "bDeferRender": true,
        "bDestroy": true,
        "bInfiniteScroll": true,
        "bPaginate": false,
        "bProcessing": true,
        "oColVis": {"activate": "mouseover", "aiExclude": [0]},
        "oLanguage": {"sSearch": "Filter results:",
                      "sZeroRecords": "No results found."},
        "sDom": "<\"#list-result-table_colvis\"C>frltip"
    });
    if (location.search.length > 0) {
        var method = location.pathname.split("/").pop();
        Rosie.show(method);
        if (method == "search" || method == "query") {
            Rosie.cookie_set("method", method);
            Rosie.cookie_set("method_params", location.search);
        }
    }
    else {
        Rosie.show("search");
        var method = Rosie.cookie_get("method");
        var method_params = Rosie.cookie_get("method_params");
        if (method && method_params) {
            location = method + method_params;
        }
    }
    Rosie.query_groups_toggle();
    $(".infodate").each(function(i) {
        var timestamp = $(this).text()*1000;
        d = new Date(timestamp).toLocaleString();
        $(this).text(d);
    });
});