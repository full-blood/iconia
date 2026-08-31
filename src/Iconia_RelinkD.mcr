/*
================================================================================
Script Name: Iconia_RelinkD
Category: Iconia
Description: Propose le relink des textures de D:\CG Library\ vers L:\,
uniquement lorsque le fichier cible existe.
================================================================================
*/
macroScript Iconia_RelinkD
category:"Iconia"
tooltip:"Relink D CG Library vers L"
buttonText:"Relink D to L"
(
try(destroyDialog IconiaRelinkDDialog)catch()

    struct IconiaRelinkDItem (sourcePath, targetPath, targetExists)

    fn iconiaRelinkD_isLibraryPath path =
    (
        if path == undefined or path == "" then return false
        local normalized = substituteString path "/" "\\"
        matchPattern normalized pattern:"D:\\CG Library\\*" ignoreCase:true
    )

    fn iconiaRelinkD_getTargetPath sourcePath =
    (
        local normalized = substituteString sourcePath "/" "\\"
        local prefixLength = "D:\\CG Library\\".count
        "L:\\" + (substring normalized (prefixLength + 1) -1)
    )

    fn iconiaRelinkD_collectMapInstances =
    (
        local maps = #()
        try(join maps (getClassInstances BitmapTexture))catch()
        try(join maps (getClassInstances CoronaBitmap))catch()
        try(join maps (getClassInstances VRayBitmap))catch()
        maps
    )

    fn iconiaRelinkD_collectCandidates =
    (
        local candidates = #()
        local seenPaths = #()
        for mapInstance in (iconiaRelinkD_collectMapInstances()) do
        (
            local sourcePath = ""
            try(sourcePath = mapInstance.filename)catch()
            if sourcePath != undefined and sourcePath != "" and iconiaRelinkD_isLibraryPath sourcePath do
            (
                local normalized = substituteString sourcePath "/" "\\"
                if (findItem seenPaths (toLower normalized)) == 0 do
                (
                    append seenPaths (toLower normalized)
                    local targetPath = iconiaRelinkD_getTargetPath normalized
                    append candidates (IconiaRelinkDItem sourcePath:normalized targetPath:targetPath targetExists:(doesFileExist targetPath))
                )
            )
        )
        candidates
    )

    fn iconiaRelinkD_compareItems a b =
    (
        if (toLower a.sourcePath) < (toLower b.sourcePath) then -1
        else if (toLower a.sourcePath) > (toLower b.sourcePath) then 1
        else 0
    )

    fn iconiaRelinkD_relinkAllInstances sourcePath targetPath =
    (
        local relinked = 0
        local expectedPath = toLower (substituteString sourcePath "/" "\\")
        for mapInstance in (iconiaRelinkD_collectMapInstances()) do
        (
            local currentPath = ""
            try(currentPath = mapInstance.filename)catch()
            if currentPath != undefined and currentPath != "" do
            (
                local normalizedCurrent = toLower (substituteString currentPath "/" "\\")
                if normalizedCurrent == expectedPath do
                (
                    try
                    (
                        mapInstance.filename = targetPath
                        relinked += 1
                    )catch()
                )
            )
        )
        relinked
    )

    rollout IconiaRelinkDDialog "Iconia - Relink D vers L" width:1180 height:590
    (
        label lbl_description "Textures trouvées sous D:\\CG Library\\. Sélectionnez celles à relinker vers L:\\ ; seules les cibles existantes seront modifiées." pos:[20,15] width:1140 height:18
        label lbl_left "Textures disponibles sur D: (CG Library)" pos:[20,45] width:500 height:18
        label lbl_right "Textures sélectionnées pour relink vers L:" pos:[630,45] width:520 height:18
        dotNetControl lb_available "System.Windows.Forms.ListBox" pos:[20,68] width:540 height:440
        dotNetControl lb_selected "System.Windows.Forms.ListBox" pos:[620,68] width:540 height:440
        button btn_add ">>" pos:[570,255] width:40 height:30 tooltip:"Ajouter la sélection au relink"
        button btn_remove "<<" pos:[570,300] width:40 height:30 tooltip:"Retirer la sélection du relink"
        button btn_refresh "Actualiser" pos:[20,530] width:105 height:30
        button btn_relink "Relinker la sélection" pos:[850,530] width:180 height:30
        button btn_close "Fermer" pos:[1060,530] width:100 height:30

        local availableItems = #()
        local selectedItems = #()

        fn initListBox listBox =
        (
            listBox.HorizontalScrollbar = true
            listBox.SelectionMode = (dotNetClass "System.Windows.Forms.SelectionMode").MultiExtended
            listBox.Font = dotNetObject "System.Drawing.Font" "Consolas" 9 (dotNetClass "System.Drawing.FontStyle").Regular
        )

        fn leftDisplay item =
        (
            local targetStatus = if item.targetExists then "OK" else "MANQUANT"
            "[" + targetStatus + "] " + item.sourcePath
        )

        fn rightDisplay item =
        (
            local targetStatus = if item.targetExists then "OK" else "MANQUANT"
            "[" + targetStatus + "] " + item.targetPath
        )

        fn refreshDisplay =
        (
            lb_available.Items.Clear()
            lb_selected.Items.Clear()
            for item in availableItems do lb_available.Items.Add (leftDisplay item)
            for item in selectedItems do lb_selected.Items.Add (rightDisplay item)
        )

        fn refreshCandidates =
        (
            availableItems = iconiaRelinkD_collectCandidates()
            selectedItems = #()
            qsort availableItems iconiaRelinkD_compareItems
            refreshDisplay()
        )

        fn moveSelected sourceItems destinationItems selectedIndices =
        (
            for i = selectedIndices.count - 1 to 0 by -1 do
            (
                local index = selectedIndices.Item[i] + 1
                append destinationItems sourceItems[index]
                deleteItem sourceItems index
            )
        )

        on IconiaRelinkDDialog open do
        (
            initListBox lb_available
            initListBox lb_selected
            refreshCandidates()
        )

        on btn_refresh pressed do
        (
            refreshCandidates()
        )

        on btn_add pressed do
        (
            moveSelected availableItems selectedItems lb_available.SelectedIndices
            qsort selectedItems iconiaRelinkD_compareItems
            refreshDisplay()
        )

        on btn_remove pressed do
        (
            moveSelected selectedItems availableItems lb_selected.SelectedIndices
            qsort availableItems iconiaRelinkD_compareItems
            refreshDisplay()
        )

        on lb_available DoubleClick sender args do
        (
            if lb_available.SelectedIndex >= 0 do
            (
                moveSelected availableItems selectedItems lb_available.SelectedIndices
                qsort selectedItems iconiaRelinkD_compareItems
                refreshDisplay()
            )
        )

        on lb_selected DoubleClick sender args do
        (
            if lb_selected.SelectedIndex >= 0 do
            (
                moveSelected selectedItems availableItems lb_selected.SelectedIndices
                qsort availableItems iconiaRelinkD_compareItems
                refreshDisplay()
            )
        )

        on btn_relink pressed do
        (
            if selectedItems.count == 0 then
            (
                messageBox "Aucune texture sélectionnée." title:"Iconia - Relink D vers L"
            )
            else
            (
                local validItems = #()
                local missingCount = 0
                for item in selectedItems do
                (
                    item.targetExists = doesFileExist item.targetPath
                    if item.targetExists then
                    (
                        append validItems item
                    )
                    else
                    (
                        missingCount += 1
                    )
                )

                if validItems.count == 0 then
                (
                    refreshDisplay()
                    messageBox "Aucune texture cible n'existe sur L:. Aucun relink n'a été effectué." title:"Iconia - Relink D vers L"
                )
                else
                (
                    local confirmation = (validItems.count as string) + " texture(s) seront relinkées de D:\\CG Library\\ vers L:\\."
                    if missingCount > 0 do confirmation += "\n\n" + (missingCount as string) + " texture(s) cible(s) manquante(s) seront ignorées."
                    if queryBox confirmation title:"Confirmer le relink" then
                    (
                        local relinkedInstances = 0
                        undo "Iconia Relink D CG Library vers L" on ( for item in validItems do ( relinkedInstances += iconiaRelinkD_relinkAllInstances item.sourcePath item.targetPath ) )
                        refreshCandidates()
                        messageBox ((validItems.count as string) + " texture(s) relinkée(s).\n" + (relinkedInstances as string) + " instance(s) de map mise(s) à jour.") title:"Iconia - Relink terminé"
                    )
                )
            )
        )

        on btn_close pressed do
        (
            destroyDialog IconiaRelinkDDialog
        )
    )

createDialog IconiaRelinkDDialog style:#(#style_titlebar, #style_sysmenu, #style_toolwindow)
)
