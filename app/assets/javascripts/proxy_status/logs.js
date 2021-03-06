function filterLogsReset() {
  var table = $('#table-proxy-status-logs').dataTable();
  for (var i = 0; i <= 2; i++) {
    table.fnFilter('', i);
  }
}

function filterLogsByLevel(filter) {
  filterLogsReset();
  var table = $('#table-proxy-status-logs').dataTable();
  table.fnFilter(filter, 1, true, false);
}

function filterLogsByMessage(expression) {
  filterLogsReset();
  changeFilterSelection(1);
  var table = $('#table-proxy-status-logs').dataTable();
  table.fnFilter('ERROR|FATAL', 1, true, false);
  table.fnFilter(expression, 2, true, false);
}

function changeFilterSelection(index) {
  var filter = $('#logs-filter');
  filter[0].options[index].selected = true
  filter.trigger('change');
  filterLogsByLevel(filter.val());
}

function activateLogsDataTable() {
  $('#table-proxy-status-logs').dataTable({
    "sDom": "<'row'<'col-md-6'f>r>t<'row'<'col-md-6'i><'col-md-6'p>>",
    "sPaginationType": "bootstrap",
    "aoColumnDefs": [{
      "mRender": function ( data, type, row ) {
        return new Date(data * 1000).toLocaleString();
      },
      "sWidth": "15%",
      "aTargets": [0]
    },{
      "sWidth": "10%",
      "aTargets": [1]
    }]});
  var filter = $('#logs-filter');
  activate_select2(filter);
  filter.on('change', function() { filterLogsByLevel(filter.val()) });

  $('#logEntryModal').on('show.bs.modal', function (event) {
    var link = $(event.relatedTarget);
    var modal = $(this);
    var datetime = new Date(link.data('time') * 1000);
    modal.find('#modal-bt-timegmt').text(datetime.toUTCString());
    modal.find('#modal-bt-time').text(datetime.toLocaleString());
    modal.find('#modal-bt-level').text(link.data('level'));
    if (link.data('message')) modal.find('#modal-bt-message').text(link.data('message'));
    if (link.data('backtrace')) modal.find('#modal-bt-backtrace').text(link.data('backtrace'));
  })
}

function expireLogs(item, from) {
  table_url = item.getAttribute('data-url');
  errors_url = item.getAttribute('data-url-errors');
  modules_url = item.getAttribute('data-url-modules');
  if (table_url && errors_url && modules_url) {
    $.ajax({
      type: 'POST',
      url: table_url,
      data: 'from=' + from,
      success: function(result) {
        $("#logs").html(result);
        activateLogsDataTable();
      },
      complete: function(){
        reloadOnAjaxComplete(item);
      }
    })
    $.ajax({
      type: 'GET',
      url: errors_url,
      success: function(result) {
        $("#ajax-errors-card").html(result);
      },
      complete: function(){
        reloadOnAjaxComplete(item);
      }
    })
    $.ajax({
      type: 'GET',
      url: modules_url,
      success: function(result) {
        $("#ajax-modules-card").html(result);
      },
      complete: function(){
        reloadOnAjaxComplete(item);
      }
    })
  }
}
