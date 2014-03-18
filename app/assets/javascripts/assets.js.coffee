jQuery ->
  app = new AssetEvents()

class AssetEvents
  constructor: ->
    @cacheElements()
    @bindEvents()

  cacheElements: ->
    # variables
    @assets = []
    @assetIds = []
    @proceeding_type = null
    @glyphiconOk= '<span class="glyphicon glyphicon-ok"></span>'
    @glyphiconUnchecked= '<span class="text-muted glyphicon glyphicon-unchecked"></span>'
    # containers
    @$selectUserAssets = $('#select-user-assets')
    @$selectUser = $('#select-user')
    @$container = $('#assig_devol')
    @$displayUserAssets = $('#display-user-assets')
    # forms & inputs
    @$building = $('#building')
    @$department = $('#department')
    @$user = $('#user')
    # buttons
    @$btnAssignation = $('#btn_assignation')
    @$btnDevolution = $('#btn_devolution')
    @$btnCancel = $('#btn_cancel')
    # Hogan templates
    @$templateAssigDevol = Hogan.compile $('#tpl_assig_devol').html() || ''
    @$templateFixedAssets = Hogan.compile $('#tpl-fixed-assets').html() || ''
    # urls
    @not_assigned_url = '/assets/not_assigned'
    @assigned_url = '/assets/assigned'
    @display_assets_url = '/assets/assign'
    @deallocate_assets_url = '/assets/deallocate'
    @proceedings_url = '/proceedings'
    # Hogan template elements
    @cacheElementsTpl()

  cacheElementsTpl: ->
    @$btnCancelAssig = $('#btn_cancel_assig')
    @$btnContinue = $('#btn_continue')
    @$btnAccept = $('#btn_accept')
    @$btnCancel_ = $('#btn_cancel_')
    @$btnSend = $('#btn-send')
    @$code = $('#code')

  bindEvents: ->
    if @$building?
      @$department.remoteChained(@$building.selector, '/assets/departments.json')
      @$user.remoteChained(@$department.selector, '/assets/users.json')
    $(document).on 'click', @$btnAssignation.selector, (e) => @displayContainer(e, 'E', @not_assigned_url)
    $(document).on 'click', @$btnDevolution.selector, (e) => @displayContainer(e, 'D', @assigned_url)
    $(document).on 'click', @$btnCancel.selector, (e) => @redirectToAssets(e)
    $(document).on 'click', @$btnCancelAssig.selector, (e) => @hideContainer(e)
    $(document).on 'click', @$btnContinue.selector, (e) => @sendAssignation(e)
    $(document).on 'click', @$btnCancel_.selector, (e) => @displaySelectUserAsset(e)
    $(document).on 'click', @$btnAccept.selector, (e) => @generatePDF(e)
    $(document).on 'click', @$btnSend.selector, (e) => @checkAssetIfExists(e)

  displayContainer: (e, proceeding_type, url) ->
    e.preventDefault()
    if @checkSelectedUser()
      @proceeding_type = proceeding_type # E = Entrega, D = Devolución
      @$selectUser.hide()
      @displayAllAssets(url)
    else
      alert('Seleccione Edificio, Departamento, y Usuario')

  hideContainer: (e) ->
    e.preventDefault()
    @$container.html('').hide()
    @$selectUser.show()
    @$btnCancel.get(0).focus()

  checkSelectedUser: ->
    @$building.val() && @$department.val() && @$user.val()

  sendAssignation: (e) ->
    e.preventDefault()
    assets_ = @$container.find('form.selected-assets input[type=hidden]').filter(-> @.value != '').serialize()
    if @isAssignation()
      url = @display_assets_url
      message = 'Debe asignar al menos un activo'
    else
      url = @deallocate_assets_url
      message = 'Seleccione al menos un activo para devolver'
    if assets_
      assets_ = assets_ + '&user_id=' + @$user.val()
      $.getJSON url, assets_, (data) => @renderSelectedAssets(data)
    else
      alert message

  displaySelectUserAsset: (e) ->
    e.preventDefault()
    @$displayUserAssets.hide()
    @$selectUserAssets.show()
    @$code.slideDown -> @.focus()

  generatePDF: (e) ->
    e.preventDefault()
    json_data = { user_id: @$user.val(), asset_ids: @assetIds, proceeding_type: @proceeding_type }
    $.post @proceedings_url, { proceeding: json_data }, null, 'script'

  checkAssetIfExists: (e) ->
    e.preventDefault()
    code = @$code.val().trim()
    if code
      if (asset_id = @searchInAssets(code)) > 0
        @selectDeselectAssetRow(asset_id)
      else
        alert "El código de Activo '#{code}' no se encuentra en la lista"
    else
      alert 'Introduzca un código de Activo'
    @$code.select()

  searchInAssets: (code) ->
    asset_id = 0
    $.each @assets, (key, obj) ->
      asset_id = obj.id if obj.code is code
    return asset_id

  selectDeselectAssetRow: (asset_id) ->
    $input = $("#asset_#{asset_id}")
    if $input.hasClass('info')
      $input.removeClass('info')
      $input.find('td:last-child').html(@glyphiconUnchecked)
      $input.find('td:first-child input[type=hidden]').val(null)
    else
      $input.addClass('info')
      $input.find('td:last-child').html(@glyphiconOk)
      $input.find('td:first-child input[type=hidden]').val(asset_id)

  renderSelectedAssets: (data) ->
    @assetIds = $.map(data.assets, (val, i) -> val.id)
    @$selectUserAssets.hide()
    @$displayUserAssets.html @$templateFixedAssets.render(data)
    @$displayUserAssets.show()
    @cacheElementsTpl()
    @$btnCancel_.get(0).focus()

  displayAllAssets: (url)->
    user_data = { user_id: @$user.val() }
    $.getJSON url, user_data, (data) => @renderTemplate(data)

  renderTemplate: (data) ->
    @assets = data.assets
    @$container.html @$templateAssigDevol.render(data)
    @$container.show()
    @cacheElementsTpl()
    @$code.slideDown -> @.focus()

  redirectToAssets: (e) ->
    e.preventDefault()
    window.location = @proceedings_url

  isAssignation: ->
    @proceeding_type is 'E'
