/*
================================================================================
Script Name: Iconia_TemplateLayer
Category: Iconia
Description: Add usual layers
================================================================================
*/

macroScript Iconia_TemplateLayer
category:"Iconia"
buttonText:"Template Layers"
tooltip:"Add usual layers"
(
	try(destroyDialog rIconiaLayers)catch()
-- 	----------------------------------------------------------------------
	-- INI
	----------------------------------------------------------------------

	local iniPath = (getDir #userMacros + "\\iconia_settings.ini")

	fn createDefaultIni =
	(
		if not doesFileExist iniPath then
		(
			setINISetting iniPath "Layers" "List" "MOD_Ceiling|MOD_DoorsWindows|MOD_Floor|MOD_Walls|#Lights|#Cameras|#DWG"
		)
	)

	fn getLayerList =
	(
		createDefaultIni()

		local str = getINISetting iniPath "Layers" "List"

		if str == "" then
			#()
		else
			filterString str "|"
	)

	fn saveLayerList layers =
	(
		local str = ""

		for i = 1 to layers.count do
		(
			str += layers[i]

			if i < layers.count then
				str += "|"
		)

		setINISetting iniPath "Layers" "List" str
	)

	----------------------------------------------------------------------
	-- LAYERS
	----------------------------------------------------------------------

	fn createLayerIfMissing layerName =
	(
		if (LayerManager.getLayerFromName layerName) == undefined then
		(
			LayerManager.newLayerFromName layerName
			true
		)
		else
		(
			false
		)
	)

	----------------------------------------------------------------------
	-- UI
	----------------------------------------------------------------------

	rollout rIconiaLayers "Layers name - Template" width:320 height:360
	(
		listbox lb_layers "" width:290 height:12

		group "Layer Name"
		(
			edittext edt_layer "" width:290
		)

		button btn_add "Add to List" width:140 across:2
		button btn_rename "Rename" width:140

		button btn_delete "Delete" width:290

		group "Scene"
		(
			button btn_addSelected "Add Selected to Layer" width:290
			button btn_addAll "Add All to Layers" width:290
		)

		------------------------------------------------------------------
		-- Helpers
		------------------------------------------------------------------

		fn reloadList =
		(
			lb_layers.items = getLayerList()
		)

		------------------------------------------------------------------
		-- Events
		------------------------------------------------------------------

		on rIconiaLayers open do
		(
			reloadList()
		)

		on lb_layers selected idx do
		(
			if idx > 0 then
				edt_layer.text = lb_layers.items[idx]
		)

		on btn_add pressed do
		(
			local newName = trimRight (trimLeft edt_layer.text)

			if newName == "" then
			(
				messageBox "Please enter a layer name."
				return()
			)

			local layers = getLayerList()

			if findItem layers newName > 0 then
			(
				messageBox "Layer already exists in the list."
				return()
			)

			append layers newName

			saveLayerList layers
			reloadList()

			lb_layers.selection = layers.count
		)

		on btn_rename pressed do
		(
			if lb_layers.selection == 0 then
			(
				messageBox "Select a layer first."
				return()
			)

			local newName = trimRight (trimLeft edt_layer.text)

			if newName == "" then
			(
				messageBox "Please enter a layer name."
				return()
			)

			local layers = getLayerList()

			layers[lb_layers.selection] = newName

			saveLayerList layers
			reloadList()

			lb_layers.selection = amin lb_layers.selection layers.count
		)

		on btn_delete pressed do
		(
			if lb_layers.selection == 0 then
			(
				messageBox "Select a layer first."
				return()
			)

			local layers = getLayerList()

			deleteItem layers lb_layers.selection

			saveLayerList layers
			reloadList()

			edt_layer.text = ""
		)

		on btn_addSelected pressed do
		(
			if lb_layers.selection == 0 then
			(
				messageBox "Select a layer first."
				return()
			)

			local layerName = lb_layers.items[lb_layers.selection]

			createLayerIfMissing layerName
		)

		on btn_addAll pressed do
		(
			local layers = getLayerList()

			for layerName in layers do
			(
				createLayerIfMissing layerName
			)

			messageBox ((layers.count as string) + " layer(s) processed.")
		)

	)

	createDialog rIconiaLayers style:#(#style_titlebar, #style_sysmenu, #style_toolwindow)
)