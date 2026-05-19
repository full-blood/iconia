/*
================================================================================
Script Name: Iconia_FileChecker
Category: Iconia
Description: Outil de vérification global avant d'intégrer un asset dans la bibliothèque 3D.
             Intègre les étapes : Corona & Clean Reset, Filename, Maps, Pivots, 
             Wirecolor, Layers, Names, Preview, et Keywords.
================================================================================
*/

macroScript Iconia_FileChecker
    category:"Iconia" 
    tooltip:"File Checker"
    buttonText:"File Checker"
(
    local rlMasterChecker
    local rl_selectImage
    local rl_Splash

    try(DestroyDialog rlMasterChecker) catch()
    try(DestroyDialog rl_selectImage) catch()

    -- ===========================================================
    -- VARIABLES GLOBALES ET CACHE (Partagées entre Splash et Main)
    -- ===========================================================
    struct CategoryDataStruct ( catName, subcats = #() )
    local database = #()
    local keyword_library = #()
    local netKeywords_Cache = undefined
    local step9_Initialized = false
	local folderAliases = #()

    fn toNetArray arr = (
        local na = dotNetObject "System.String[]" arr.count
        for i = 1 to arr.count do na.SetValue arr[i] (i-1)
        na
    )

    fn fillComboBox ctrl arr = (
        ctrl.BeginUpdate()
        ctrl.Items.Clear()
        if arr.count > 0 do ctrl.Items.AddRange (toNetArray arr)
        ctrl.EndUpdate()
    )
	
	fn resolveFolderAlias rawName = (
		for pair in folderAliases do (
			if (stricmp pair[1] rawName == 0) do return pair[2]
		)
		return rawName  -- pas d'alias trouvé, on retourne tel quel
	)

    -- ===========================================================
    -- FENÊTRE DE CHARGEMENT (SPLASH SCREEN)
    -- ===========================================================
    fn rl_Splash =
    (
        -- LOAD DB CSV
        local csvPath = "L:\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\MaxStack-MaxStack_FileChecker_Categories_List.csv"
        database = #()
        if doesFileExist csvPath do (
            local f = openFile csvPath
            while not eof f do (
                local parts = filterString (readLine f) ";"
                if parts.count >= 2 do (
                    local cName    = trimLeft (trimRight parts[1])
                    local sName    = trimLeft (trimRight parts[2])
                    local foundCat = undefined
                    for d in database do ( if d.catName == cName do foundCat = d )
                    if foundCat == undefined do ( foundCat = CategoryDataStruct catName:cName; append database foundCat )
                    appendIfUnique foundCat.subcats sName
                )
            )
            close f
        )

        -- LOAD KEYWORDS LIBRARY + PRÉ-CALCUL .NET
        local txtPathLib = "L:\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\MaxStack-MaxStack_FileChecker_Keywords_List.txt"
        keyword_library = #()
        if doesFileExist txtPathLib do (
            local fLib = openFile txtPathLib
            while not eof fLib do (
                local l = trimLeft (trimRight (readLine fLib))
                if l != "" do appendIfUnique keyword_library l
            )
            close fLib
            sort keyword_library
            
            -- Précalcul .NET pendant le chargement
            netKeywords_Cache = toNetArray keyword_library 
        )

        -- Ferme le Splash et ouvre la fenêtre principale
        try(DestroyDialog rlMasterChecker) catch()
        CreateDialog rlMasterChecker style:#(#style_titlebar, #style_sysmenu)
    )

    -- ===========================================================
    -- ROLLOUT SECONDAIRE : SÉLECTION D'IMAGE
    -- ===========================================================
    rollout rl_selectImage "Select preview image" width:620 height:560 (
        local imageFiles = #()
        local imgfolder = ""
        local imgbaseName = ""

        listbox lb_images "" pos:[10,10] width:600 height:15
        dotNetControl pb_preview "System.Windows.Forms.PictureBox" pos:[10,260] width:600 height:240
        button bt_ok "Use selected image" width:200 align:#center offset:[0,5]

        on rl_selectImage open do ( 
            pb_preview.SizeMode = (dotNetClass "System.Windows.Forms.PictureBoxSizeMode").Zoom
            pb_preview.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle
            pb_preview.BackColor = (dotNetClass "System.Drawing.Color").FromARGB 50 50 50 
            
            imgfolder = maxFilePath
            imgbaseName = getFilenameFile maxFileName
            imageFiles = #()
            
            for ext in #(".jpg", ".jpeg", ".png", ".bmp") do (
                join imageFiles (getFiles (imgfolder + "*" + ext))
            )
            
            lb_images.items = for f in imageFiles collect (filenameFromPath f)
        )
        
        on lb_images selected idx do ( 
            try(if pb_preview.Image != undefined do pb_preview.Image.Dispose())catch()
            try(pb_preview.Image = (dotNetObject "System.Drawing.Bitmap" imageFiles[idx]))catch() 
        )
        
        on bt_ok pressed do (
            if lb_images.selection != 0 then (
                local sourceFile = imageFiles[lb_images.selection]
                local ext = getFilenameType sourceFile
                local destFile = imgfolder + imgbaseName + ext
                
                try(if pb_preview.Image != undefined do pb_preview.Image.Dispose())catch()
                
                if copyFile sourceFile destFile then ( 
                    destroyDialog rl_selectImage
                    try(rlMasterChecker.checkPreviewImage())catch() 
                ) else (
                    messageBox "Erreur lors de la copie du fichier." title:"Preview image"
                )
            ) else (
                messageBox "Sélectionne une image." title:"Preview image"
            )
        )
        
        on rl_selectImage close do ( 
            try(if pb_preview.Image != undefined do pb_preview.Image.Dispose())catch() 
        )
    )

    -- ===========================================================
    -- ROLLOUT PRINCIPAL : MASTER CHECKER
    -- ===========================================================
    rollout rlMasterChecker "MaxStack — Master Checker" width:800 height:600
    (
        local updateChecklistUI, hideAllUI, showCurrentStepUI, switchStep
        local doCheckCorona, completeStep1, doCleanReset, checkSceneMaterials, collectMaterials
        local doCheckFilename, cleanMaxFileName, doRenameOnDisk, completeStep2
        local collectAllBitmaps, checkBitmapStatus, relinkBitmaps, doStep3_Scan, doStep3_Relink, completeStep3
        local rPivot, rGrpPivot, hasDiffScale
        local wColor, listAllLayers
        local getPrefix, updateNameList, renameItemFromList
        local checkPreviewImage
        local initDotNetCombobox, getAiKeywords, initStep9Keywords

        -- ===========================================================
        -- COLONNE GAUCHE : CHECKLIST
        -- ===========================================================
        label lbl_step1 "[ . ] Check Corona & Reset" pos:[15, 20]  width:145 height:16
        label lbl_step2 "[   ] Check filename"       pos:[15, 45]  width:145 height:16
        label lbl_step3 "[   ] Check maps"           pos:[15, 70]  width:145 height:16
        label lbl_step4 "[   ] Check pivots"         pos:[15, 95]  width:145 height:16
        label lbl_step5 "[   ] Check wirecolor"      pos:[15, 120] width:145 height:16
        label lbl_step6 "[   ] Check layers"         pos:[15, 145] width:145 height:16
        label lbl_step7 "[   ] Check names"          pos:[15, 170] width:145 height:16
        label lbl_step8 "[   ] Check preview"        pos:[15, 195] width:145 height:16
        label lbl_step9 "[   ] Check keywords"       pos:[15, 220] width:145 height:16

        button btn_prev "<< Prev" pos:[15, 560] width:65 height:25 enabled:false
        button btn_next "Next >>" pos:[85, 560] width:65 height:25
        label lbl_sep "" pos:[160, 15] width:1 height:565 style_sunkenedge:true

        -- ===========================================================
        -- UI ÉTAPE 1 : CORONA & CLEAN RESET
        -- ===========================================================
        label lbl_reload "⏳ Chargement en cours..." pos:[400,300] visible:true
        listBox lst_log_s1 "" pos:[180,20] width:590 height:12 visible:false
        button btn_main_s1 "CHECK CORONA\n& CLEAN RESET" pos:[405,400] width:140 height:60 align:#center visible:false
        button btn_converter_s1 "OPEN CORONA\nCONVERTER" pos:[265,350] width:140 height:60 visible:false
        button btn_done_s1 "CORONA\nOK ✔" pos:[485,350] width:140 height:60 visible:false
        button btn_recheck_s1 "RECHECK" pos:[375,450] width:140 height:60 align:#center visible:false

        -- ===========================================================
        -- UI ÉTAPE 2 : FILE CHECKER
        -- ===========================================================
        listBox lst_log_s2 "" pos:[180,20] width:590 height:12 visible:false
        label lbl_prev_title_s2 "Preview :" pos:[180,208] width:590 height:16 visible:false
        edittext edt_before_s2 "" pos:[180,228] width:590 height:22 readOnly:true visible:false
        label lbl_arrow_s2 "▼" pos:[465,254] width:30 height:18 align:#center visible:false
        edittext edt_after_s2  "" pos:[180,274] width:590 height:22 readOnly:true visible:false
        button btn_main_s2 "RETRY CHECK" pos:[635,525] width:120 height:60 align:#center visible:false
        button btn_confirm_s2 "RENAME FILE\nON DISK" pos:[405,400] width:120 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 3 : MAPS CHECKER
        -- ===========================================================
        listBox lst_log_s3 "" pos:[180,20] width:590 height:16 visible:false
        checkbox chk_fixOutside_s3 "Relink 'Outside' maps to local folder if found" pos:[180,270] checked:true visible:false
        
        button btn_force_s3 "Open Asset Tracking" pos:[190,515] width:120 height:60 enabled:false visible:false
        button btn_recheck_s3 "RECHECK" pos:[343,515] width:120 height:60 visible:false
        button btn_remove_missing_s3 "REMOVE MISSING" pos:[496,515] width:120 height:60 visible:false
        button btn_main_s3 "CHECK MAPS" pos:[496,515] width:120 height:60 align:#center visible:false
        button btn_done_s3 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 4 : PIVOTS
        -- ===========================================================
        listBox lst_log_s4 "" pos:[180,20] width:590 height:12 visible:false
        button btn_piv_each_s4 "RESET EACH PIVOT" pos:[310,515] width:140 height:60 visible:false
        button btn_piv_grp_s4 "RESET GROUPED PIVOT" pos:[470,515] width:140 height:60 visible:false
        button btn_done_s4 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 5 : WIRECOLOR
        -- ===========================================================
        listBox lst_log_s5 "" pos:[180,20] width:590 height:12 visible:false
        button btn_wire_s5 "FIX BLACK WIRECOLOR" pos:[470,515] width:140 height:60 visible:false
        button btn_done_s5 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 6 : LAYERS (Bouton Combiné)
        -- ===========================================================
        listBox lst_log_s6 "Layers in scene:" pos:[180,20] width:590 height:16 visible:false
        button btn_lay_fix_s6 "MOVE ALL TO LAYER 0\n& REMOVE UNUSED" pos:[375,350] width:200 height:80 visible:false
        button btn_done_s6 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 7 : NAMES
        -- ===========================================================
		multiListBox lst_names_s7 "Object Names:" pos:[180, 20] width:590 height:26 visible:false
		
        label lbl_n_pref "Prefix:" pos:[510,405] width:60 height:16 visible:false
        edittext edt_n_pref "" pos:[570,403] width:200 height:20 visible:false
        label lbl_n_base "Base Name:" pos:[510,430] width:60 height:16 visible:false
        edittext edt_n_base "" pos:[570,428] width:200 height:20 visible:false
        
        button btn_n_all "Name All" pos:[510,460] width:80 height:30 visible:false
        button btn_n_grp "Name Group" pos:[595,460] width:85 height:30 visible:false
        button btn_n_sel "Name Selected" pos:[685,460] width:85 height:30 visible:false
        
        label lbl_n_search "Search:" pos:[180,405] width:60 height:16 visible:false
        edittext edt_n_search "" pos:[240,403] width:200 height:20 visible:false
        label lbl_n_repl "Replace:" pos:[180,430] width:60 height:16 visible:false
        edittext edt_n_repl "" pos:[240,428] width:200 height:20 visible:false
        button btn_n_replace "Search & Replace" pos:[180,460] width:260 height:30 visible:false

        button btn_done_s7 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 8 : PREVIEW
        -- ===========================================================
        listBox lst_log_s8 "" pos:[180,20] width:590 height:12 visible:false
        button btn_prev_fix_s8 "ASSIGN PREVIEW IMAGE" pos:[375,350] width:200 height:80 visible:false
        button btn_done_s8 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 9 : KEYWORDS
        -- ===========================================================
        label lbl_cat_s9 "Category:" pos:[-1000,-1000] width:80 height:16 
        dotNetControl cbx_cat "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:200 height:21 
        label lbl_subcat_s9 "Subcat:" pos:[-1000,-1000] width:80 height:16 
        dotNetControl cbx_subcat "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:200 height:21 
        
        button btn_ai_s9 "AI Search" pos:[-1000,-1000] width:100 height:45 
        button btn_done_s9 "SAVE OK FILE" pos:[-1000,-1000] width:150 height:45 
        button btn_final_validate_s9 "FINAL VALIDATE ✔" pos:[-1000,-1000] width:140 height:60

        label lbl_key_s9 "Keywords:" pos:[-1000,-1000] width:590 height:16 
        dotNetControl cbx_k1 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k2 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k3 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k4 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k5 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        
        dotNetControl cbx_k6 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k7 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k8 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k9 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k10 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 

        dotNetControl cbx_k11 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k12 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k13 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k14 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k15 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 

        -- ===========================================================
        -- VARIABLES D'ÉTAT GLOBALES
        -- ===========================================================
        local currentStep   = 1
        local stepStates    = #(0,0,0,0,0,0,0,0,0) 
        local stepNames     = #("Check Corona & Reset", "Check filename", "Check maps", "Check pivots", "Check wirecolor", "Check layers", "Check names", "Check preview", "Check keywords")
        
        local step2_state   = 1
        local cleanedName   = ""

        local step3_state       = 1
        local bitmapList        = #()
        local bitmapList_clean  = #()
        local totalMaps         = 0
        local missingMaps       = 0
        local relativeMaps      = 0
        local emptyMaps         = 0
        local wrongLocationMaps = 0
        local wrongLocationList = #()

        -- ===========================================================
        -- FONCTIONS GLOBALES (UI & NAV)
        -- ===========================================================
        fn updateChecklistUI =
        (
            local labels = #(lbl_step1, lbl_step2, lbl_step3, lbl_step4, lbl_step5, lbl_step6, lbl_step7, lbl_step8, lbl_step9)
            for i = 1 to 9 do
            (
                local prefix = "[   ] "
                if stepStates[i] == 1 then prefix = "[✔] "
                else if i == currentStep then prefix = "[ . ] "
                labels[i].text = prefix + stepNames[i]
            )
            btn_prev.enabled = (currentStep > 1)
            btn_next.enabled = (currentStep < 9)
        )

        fn hideAllUI =
        (
            local allCtrls = #(
                lst_log_s1, btn_main_s1, btn_converter_s1, btn_done_s1, btn_recheck_s1,
                lst_log_s2, lbl_prev_title_s2, edt_before_s2, lbl_arrow_s2, edt_after_s2, btn_main_s2, btn_confirm_s2,
                lst_log_s3, chk_fixOutside_s3, btn_force_s3, btn_main_s3, btn_remove_missing_s3, btn_recheck_s3, btn_done_s3,
                lst_log_s4, btn_piv_each_s4, btn_piv_grp_s4, btn_done_s4,
                lst_log_s5, btn_wire_s5, btn_done_s5,
                lst_log_s6, btn_lay_fix_s6, btn_done_s6,
                lbl_n_pref, edt_n_pref, lbl_n_base, edt_n_base, btn_n_all, btn_n_grp, btn_n_sel, lbl_n_search, edt_n_search, lbl_n_repl, edt_n_repl, btn_n_replace, btn_done_s7, lst_names_s7,
                lst_log_s8, btn_prev_fix_s8, btn_done_s8,
                lbl_cat_s9, cbx_cat, lbl_subcat_s9, cbx_subcat, btn_ai_s9, btn_done_s9, btn_final_validate_s9, lbl_key_s9, cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15
            )
            for c in allCtrls where c != undefined do try(c.visible = false)catch()
			
			local s9Ctrls = #(lbl_cat_s9, cbx_cat, lbl_subcat_s9, cbx_subcat, btn_ai_s9, btn_done_s9, btn_final_validate_s9, lbl_key_s9, cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15)
			for c in s9Ctrls where c != undefined do try(c.pos = [-1000,-1000])catch()
        )

        fn showCurrentStepUI =
        (
            hideAllUI()
            if currentStep == 1 then ( for c in #(lst_log_s1) do c.visible = true; if stepStates[1] == 0 then btn_main_s1.visible = true )
            else if currentStep == 2 then ( for c in #(lst_log_s2, lbl_prev_title_s2, edt_before_s2, lbl_arrow_s2, edt_after_s2) do c.visible = true; if step2_state == 2 then btn_confirm_s2.visible = true else btn_main_s2.visible = true )
            else if currentStep == 3 then ( 
                for c in #(lst_log_s3, btn_done_s3) do c.visible = true
                if step3_state == 1 do btn_main_s3.visible = true
                if step3_state >= 2 do btn_force_s3.visible = true
                
                if step3_state == 2 do (
                    btn_main_s3.visible = true
                    if wrongLocationMaps > 0 do chk_fixOutside_s3.visible = true
                )
                if step3_state == 3 do ( -- Manquants après relink
                    btn_remove_missing_s3.visible = true
                    btn_recheck_s3.visible = true
                )
                if step3_state == 4 do btn_main_s3.visible = true -- Affiche le bouton Disabled "ALL OK"
            )
            else if currentStep == 4 then ( for c in #(lst_log_s4, btn_piv_each_s4, btn_piv_grp_s4, btn_done_s4) do c.visible = true )
            
            else if currentStep == 5 then ( 
                lst_log_s5.visible = true
                btn_done_s5.visible = true -- Affiché immédiatement
                
                local hasBlack = false
                for o in objects where o.wirecolor == (color 0 0 0) do ( hasBlack = true; exit )
                if hasBlack then (
                    lst_log_s5.items = #("⚠ Des objets ont un wirecolor noir.", "Cliquez sur le bouton pour corriger.")
                    btn_wire_s5.visible = true
                ) else (
                    lst_log_s5.items = #("✔ Aucun wirecolor noir trouvé.", "Vous pouvez cliquer sur Validate pour continuer.")
                    stepStates[5] = 1
                    updateChecklistUI()
                )
            )
            
            else if currentStep == 6 then ( for c in #(lst_log_s6, btn_lay_fix_s6, btn_done_s6) do c.visible = true )
            else if currentStep == 7 then ( for c in #(lbl_n_pref, edt_n_pref, lbl_n_base, edt_n_base, btn_n_all, btn_n_grp, btn_n_sel, lbl_n_search, edt_n_search, lbl_n_repl, edt_n_repl, btn_n_replace, btn_done_s7, lst_names_s7) do c.visible = true )
            else if currentStep == 8 then ( for c in #(lst_log_s8, btn_prev_fix_s8, btn_done_s8) do c.visible = true )
            
            else if currentStep == 9 then ( 
                lbl_cat_s9.pos=[180,20]; cbx_cat.pos=[260,19]; lbl_subcat_s9.pos=[180,45]; cbx_subcat.pos=[260,43]
                btn_ai_s9.pos=[480,18]; btn_done_s9.pos=[600,18]; btn_final_validate_s9.pos=[630,515]; lbl_key_s9.pos=[180,80]
                cbx_k1.pos=[180,100]; cbx_k2.pos=[180,125]; cbx_k3.pos=[180,150]; cbx_k4.pos=[180,175]; cbx_k5.pos=[180,200]
                cbx_k6.pos=[380,100]; cbx_k7.pos=[380,125]; cbx_k8.pos=[380,150]; cbx_k9.pos=[380,175]; cbx_k10.pos=[380,200]
                cbx_k11.pos=[580,100]; cbx_k12.pos=[580,125]; cbx_k13.pos=[580,150]; cbx_k14.pos=[580,175]; cbx_k15.pos=[580,200]
                
                for c in #(lbl_cat_s9, cbx_cat, lbl_subcat_s9, cbx_subcat, btn_ai_s9, btn_done_s9, btn_final_validate_s9, lbl_key_s9, cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15) do c.visible = true 
                
                if not step9_Initialized do (
                    initStep9Keywords()
                    step9_Initialized = true
                )
            )
        )

        -- ===========================================================
        -- FONCTIONS ÉTAPE 1 : CORONA & CLEAN RESET
        -- ===========================================================
        fn collectMaterials mat collected = (
            if mat == undefined then return collected
            if (findItem collected mat) == 0 do (
                append collected mat
                -- Va chercher dans les Multi/Sub-Object
                if superclassof mat == MaterialContainer then (
                    for i = 1 to mat.numsubs do collectMaterials mat[i] collected
                )
            )
            return collected
        )

        fn checkSceneMaterials = (
            local mats = #()
            for o in objects where o.material != undefined do collectMaterials o.material mats
            
            local badMats = #()
            for m in mats do (
                local cStr = classof m as string
                -- Autorise tout ce qui est Corona, ou les Multimatériaux.
                if not (matchPattern cStr pattern:"*Corona*") and cStr != "Multimaterial" and cStr != "Multi/Sub-Object" do (
                    append badMats m
                )
            )
            return badMats
        )

        fn doCleanReset = (
            local dir = maxFilePath
            local name = getFilenameFile maxFileName
            local backupPath = dir + name + "_backup.max"
            local tempExport = dir + name + "_CLEAN.max"

            max select all
            saveMaxFile backupPath quiet:true
            saveNodes selection tempExport quiet:true
            
            if loadMaxFile tempExport quiet:true useFileUnits:true then (
                if objects.count == 0 then (
                    lst_log_s1.items = #("ERREUR : Scène vide après nettoyage. Restauration de la sauvegarde...")
                    loadMaxFile backupPath quiet:true
                ) else (
                    saveMaxFile (dir + name + ".max") quiet:true
                    if doesFileExist tempExport do deleteFile tempExport
                    if doesFileExist backupPath do deleteFile backupPath
                    
                    lst_log_s1.items = #("✔ Clean Reset effectué avec succès !")
                    completeStep1()
                )
            ) else (
                lst_log_s1.items = #("ERREUR : Impossible de recharger la scène nettoyée.")
            )
        )

        fn doCheckCorona = (
            if maxFilePath == "" then (
                lst_log_s1.items = #("ERROR : File not saved yet.", "Sauvegardez d'abord la scène .max.")
                btn_main_s1.visible = true
                return false
            )

            local logLines = #()
            local currRend = classOf renderers.current as string
            append logLines ("Moteur de rendu actuel : " + currRend)
            
            local isCorona = matchPattern currRend pattern:"*Corona*" ignoreCase:true
            
            if not isCorona then ( 
                append logLines "⚠ ATTENTION : Le moteur n'est PAS Corona !"
                append logLines "Veuillez ouvrir le Corona Converter, convertir la scène,"
                append logLines "puis cliquer sur 'RECHECK'."
                lst_log_s1.items = logLines
                btn_main_s1.visible = false
                btn_converter_s1.visible = true
                btn_done_s1.visible = true
                btn_recheck_s1.visible = true
                return false
            )
            
            append logLines "✔ Moteur Corona détecté."
            
            local badMats = checkSceneMaterials()
            if badMats.count > 0 then (
                append logLines ""
                append logLines "⚠ MATÉRIAUX INVALIDE TROUVÉS :"
                for m in badMats do append logLines (" - " + m.name + " (" + (classof m as string) + ")")
                append logLines "Convertissez ou supprimez ces matériaux avant de continuer."
                lst_log_s1.items = logLines
                btn_main_s1.visible = false
                btn_converter_s1.visible = true
                btn_done_s1.visible = true
                btn_recheck_s1.visible = true
                return false
            )
            
            append logLines "✔ Tous les matériaux sont compatibles Corona."
            append logLines "Lancement du Clean Reset..."
            lst_log_s1.items = logLines
            
            doCleanReset()
        )

        fn completeStep1 = ( 
            stepStates[1] = 1; updateChecklistUI()
            btn_converter_s1.visible = false; btn_done_s1.visible = false; btn_main_s1.visible = false; btn_recheck_s1.visible = false
            switchStep 2
        )

        -- ===========================================================
        -- FONCTIONS ÉTAPE 2 : FILENAME
        -- ===========================================================
        fn cleanMaxFileName rawName = ( 
            local s = rawName
            local hasCorona = false
            local sLow = toLower s
            
            if (findString sLow "corona") != undefined then hasCorona = true
            
            if (findString sLow "_cr") != undefined then (
                local pos = findString sLow "_cr"
                while pos != undefined do (
                    local afterPos = pos + 3
                    local charAfter = if afterPos <= sLow.count then substring sLow afterPos 1 else ""
                    if charAfter == "" or charAfter == "_" or charAfter == "-" or charAfter == " " or (charAfter >= "0" and charAfter <= "9") then hasCorona = true
                    pos = findString sLow "_cr" (pos + 1)
                )
            )
            
            if (findString sLow "-cr") != undefined then (
                local pos = findString sLow "-cr"
                while pos != undefined do (
                    local afterPos = pos + 3
                    local charAfter = if afterPos <= sLow.count then substring sLow afterPos 1 else ""
                    if charAfter == "" or charAfter == "_" or charAfter == "-" or charAfter == " " or (charAfter >= "0" and charAfter <= "9") then hasCorona = true
                    pos = findString sLow "-cr" (pos + 1)
                )
            )
            
            fn removeYear str = (
                local result = str
                local i = 1
                while i <= result.count do (
                    local c = substring result i 1
					local isSep  = (c == "_" or c == "-" or c == " " or c == "{" or c == "[" or c == "(" or c == ".")
					local isAlph = ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z"))
                    
                    if (isSep or isAlph) and (i + 4 <= result.count) then (
                        local d1 = substring result (i+1) 1
                        local d2 = substring result (i+2) 1
                        local d3 = substring result (i+3) 1
                        local d4 = substring result (i+4) 1
                        local isYear = ((d1 == "1" and d2 == "9") or (d1 == "2" and d2 == "0")) \
                                       and (d3 >= "0" and d3 <= "9") and (d4 >= "0" and d4 <= "9")
                        
                        if isYear then (
                            local after = if (i + 5) <= result.count then (substring result (i+5) 1) else ""
                            local isEnd = (after == "" or after == "_" or after == "-" or after == " " or after == "}" or after == "]" or after == ")")
                            
                            if isEnd then (
                                local startIdx = if isSep then (i - 1 + 1) else i
                                local before = if isSep then (substring result 1 (i-1)) else (substring result 1 i)
                                local rest   = if (i + 4) < result.count then (substring result (i+5) -1) else ""
                                result = before + rest
                            ) else ( i += 1 )
                        ) else ( i += 1 )
                    ) else ( i += 1 )
                )
                return result
            )
            
            s = removeYear s
            
            local coronarenderVariants = #("_CoronaRender", "-CoronaRender", " CoronaRender", "(CoronaRender)", "_coronarender", "-coronarender", " coronarender", "(coronarender)", "_CORONARENDER", "-CORONARENDER", " CORONARENDER", "(CORONARENDER)", "CoronaRender", "coronarender", "CORONARENDER")
            for v in coronarenderVariants do s = substituteString s v ""
            local coronaVariants = #("(Corona)", "(corona)", "(CORONA)", "_Corona",  "-Corona",  " Corona", "_corona",  "-corona",  " corona", "_CORONA",  "-CORONA",  " CORONA", "Corona",   "corona",   "CORONA")
            for v in coronaVariants do s = substituteString s v ""
            local crVariants = #("_CR", "-CR", "_cr", "-cr", "_Cr", "-Cr")
            for v in crVariants do s = substituteString s v ""
            local vrayVariants = #("_VRay", "-VRay", " VRay", "(VRay)", "_vray", "-vray", " vray", "(vray)", "_VRAY", "-VRAY", " VRAY", "(VRAY)", "_Vray", "-Vray", " Vray", "(Vray)", "_VRayMtl","-VRayMtl"," VRayMtl", "VRay", "vray", "VRAY", "Vray")
            for v in vrayVariants do s = substituteString s v ""
            
            local prevS = ""
            while prevS != s do ( prevS = s; s = substituteString s "__" "_" )
            prevS = ""
            while prevS != s do ( prevS = s; s = substituteString s "--" "-" )
            while s.count > 0 do ( local last = substring s s.count 1; if last == "_" or last == "-" or last == " " or last == "}" or last == "]" or last == ")" then s = substring s 1 (s.count - 1) else exit )
			while s.count > 0 do ( local first = substring s 1 1; if first == "_" or first == "-" or first == " " or first == "{" or first == "[" or first == "(" then s = substring s 2 -1 else exit )
            
            if hasCorona then s = s + "_corona"
            return #(s, hasCorona)
        )

        fn doRenameOnDisk oldPath newBaseName = (
            local dir = getFilenamePath oldPath; local oldExt = getFilenameType oldPath; local newPath = dir + newBaseName + oldExt
            local isExactSame = (oldPath.count == newPath.count and matchPattern oldPath pattern:newPath ignoreCase:false)
            if isExactSame then return #(true, "unchanged")
            if (toLower oldPath) == (toLower newPath) then ( local tempPath = dir + newBaseName + "_TEMP" + oldExt; renameFile oldPath tempPath; if (renameFile tempPath newPath) then return #(true, newPath) else return #(false, "Case-only rename failed.") )
            if doesFileExist newPath then return #(false, "A file with that name already exists:\n" + newPath)
            if (renameFile oldPath newPath) then return #(true, newPath) else return #(false, "renameFile failed.")
        )

        fn completeStep2 = ( 
            stepStates[2] = 1; updateChecklistUI(); 
            btn_confirm_s2.visible = false; btn_main_s2.visible = true; btn_main_s2.enabled = false; btn_main_s2.text = "RENAME\nDONE ✔"; step2_state = 3 
            switchStep 3
        )

        fn doCheckFilename = (
            if maxFileName == "" then ( lst_log_s2.items = #("ERROR : File not saved yet.", "Please save your .max file first, then click RETRY."); btn_main_s2.visible = true; btn_main_s2.enabled = true; return false )
            local rawBase = getFilenameFile maxFileName; local result = cleanMaxFileName rawBase; cleanedName = result[1]; local hasCoronaFlag = result[2]
            local logLines = #(); append logLines ("File   : " + maxFileName); append logLines ("Path   : " + maxFilePath); append logLines ""
            local rawLow = toLower rawBase
            if (findString rawLow "vray") != undefined then append logLines "⚠  VRay detected → will be removed"
            if hasCoronaFlag then append logLines "✓  Corona detected → will become _corona suffix"
            local hasYear = false
            for yearSep in #("_", "-", " ") do ( for yearPfx in #("19", "20") do ( local yp = findString rawBase (yearSep + yearPfx); if yp != undefined and (yp + 4) <= rawBase.count do hasYear = true ) )
            if hasYear then append logLines "✓  Year detected → will be removed"
            local isAlreadyClean = (cleanedName.count == rawBase.count and matchPattern cleanedName pattern:rawBase ignoreCase:false)
            if isAlreadyClean then ( 
                append logLines ""; append logLines "✔  Filename is already clean. Nothing to do."
                lst_log_s2.items = logLines; edt_before_s2.text = rawBase; edt_after_s2.text = cleanedName
                completeStep2()
                return true 
            )
            append logLines ""; append logLines "Review the rename below, then confirm."; lst_log_s2.items = logLines; edt_before_s2.text = rawBase; edt_after_s2.text = cleanedName; btn_main_s2.visible = false; btn_confirm_s2.visible = true; step2_state = 2
        )

        -- ===========================================================
        -- FONCTIONS ÉTAPE 3 : MAPS
        -- ===========================================================
        fn collectAllBitmaps =
        (
            bitmapList       = #()
            bitmapList_clean = #()
            local lists = #()
            try( join lists (getClassInstances BitmapTexture) )catch()
            try( join lists (getClassInstances CoronaBitmap)  )catch()
            try( join lists (getClassInstances VRayBitmap)    )catch()

            for b in lists do (
                local fname = ""
                try( fname = b.filename )catch()
                if fname != undefined and fname != "" then (
                    appendIfUnique bitmapList b
                    appendIfUnique bitmapList_clean fname
                )
            )
            sort bitmapList_clean
            return bitmapList_clean
        )

        fn checkBitmapStatus b =
        (
            local fname = ""
            try( fname = b.filename )catch()
            if fname == undefined or fname == "" then return "EMPTY"
            if not (pathConfig.isAbsolutePath fname) then return "RELATIVE"
            if not (doesFileExist fname) then return "MISSING"
            return "OK"
        )

        fn relinkBitmaps doFixOutside =
        (
            local subFolders = #("","Map","Maps","Texture","Textures","map","maps","texture","textures")
            local scenePath  = maxFilePath
            local fixedCount = 0
            local missingCount = 0

            if scenePath == "" then (
                messageBox "Veuillez d'abord sauvegarder votre scène (.max)." title:"MaxStack - Relink"
                return #(0,0)
            )

            local allBmps = #()
            try( join allBmps (getClassInstances BitmapTexture) )catch()
            try( join allBmps (getClassInstances CoronaBitmap)  )catch()
            try( join allBmps (getClassInstances VRayBitmap)    )catch()

            for bmp in allBmps do (
                local fname = ""
                try( fname = bmp.filename )catch()
                if fname == undefined or fname == "" then continue

                local isAbs = pathConfig.isAbsolutePath fname
                local isExisting = doesFileExist fname
                local isOutside = false
                
                if isAbs and isExisting and scenePath != "" do (
                    if (findString (toLower fname) (toLower scenePath)) == undefined do isOutside = true
                )

                if not isAbs or not isExisting or (doFixOutside and isOutside) then (
                    local fNameOnly = filenameFromPath fname
                    local foundIt = false

                    for sub in subFolders while not foundIt do (
                        local testPath = scenePath
                        if sub != "" do testPath += sub + "\\"
                        testPath += fNameOnly
                        
                        if doesFileExist testPath then (
                            if (toLower fname) != (toLower testPath) do (
                                try( bmp.filename = testPath )catch()
                                foundIt = true
                                fixedCount += 1
                            )
                        )
                    )
                    if not foundIt and (not isAbs or not isExisting) then missingCount += 1
                )
            )
            atsops.refresh()
            return #(fixedCount, missingCount)
        )

        fn doStep3_Scan =
        (
            collectAllBitmaps()
            totalMaps         = bitmapList.count
            missingMaps       = 0
            relativeMaps      = 0
            emptyMaps         = 0
            wrongLocationMaps = 0
            wrongLocationList = #()

            local logLines = #()
            local scenePath = toLower maxFilePath

            for b in bitmapList do (
                local st = checkBitmapStatus b
                case st of (
                    "MISSING":  ( missingMaps  += 1 )
                    "RELATIVE": ( relativeMaps += 1 )
                    "EMPTY":    ( emptyMaps    += 1 )
                    "OK": (
                        local fname = ""
                        try( fname = b.filename )catch()
                        if fname != undefined and fname != "" and scenePath != "" then (
                            local fLow = toLower fname
                            if (findString fLow scenePath) == undefined then (
                                wrongLocationMaps += 1
                                appendIfUnique wrongLocationList (filenameFromPath fname)
                            )
                        )
                    )
                )
            )

            local okMaps = totalMaps - missingMaps - relativeMaps - emptyMaps

            append logLines "Les bitmaps doivent se trouver dans un dossier maps, textures ou à la racine du dossier."
            append logLines ""
            append logLines ("Total bitmaps found  : " + totalMaps as string)
            append logLines ("OK, in project folder: " + (okMaps - wrongLocationMaps) as string)
            append logLines ("Missing              : " + missingMaps  as string)
            append logLines ("Relative paths       : " + relativeMaps as string)
            append logLines ("Empty paths          : " + emptyMaps    as string)

            if wrongLocationMaps > 0 then (
                append logLines ("Outside project      : " + wrongLocationMaps as string + "  ⚠")
                append logLines ""
                append logLines "--- Maps outside project folder ---"
                for f in wrongLocationList do append logLines ("  ! " + f)
            ) else append logLines ("Outside project      : 0")

            if totalMaps == 0 then (
                append logLines ""
                append logLines "No bitmaps in scene."
                lst_log_s3.items = logLines
                btn_main_s3.enabled = false
                btn_main_s3.text = "NO MAPS\nFOUND"
                step3_state = 4
                showCurrentStepUI()
                return true
            )

            lst_log_s3.items = logLines

            if (missingMaps + relativeMaps + emptyMaps + wrongLocationMaps) == 0 then (
                step3_state = 4
                btn_main_s3.text = "ALL MAPS\nOK ✓"
                btn_main_s3.enabled = false
                showCurrentStepUI()
                return true
            ) else (
                step3_state = 2
                btn_main_s3.text = "RELINK\nMAPS"
                btn_force_s3.enabled = true
                showCurrentStepUI()
                return false
            )
        )

        fn doStep3_Relink =
        (
            local logLines = lst_log_s3.items
            append logLines ""
            append logLines "Auto-relinking..."
            lst_log_s3.items = logLines

            local result = relinkBitmaps (chk_fixOutside_s3.checked)
            local fixedCount   = result[1]
            local missingCount = result[2]

            collectAllBitmaps()
            local stillMissing = 0
            local stillOutside = 0
            local scenePath = toLower maxFilePath
            
            for b in bitmapList do (
                local st = checkBitmapStatus b
                if st == "MISSING" or st == "RELATIVE" then stillMissing += 1
                else if st == "OK" and scenePath != "" do (
                    local fname = ""
                    try( fname = b.filename )catch()
                    if fname != undefined and fname != "" do (
                        if (findString (toLower fname) scenePath) == undefined do stillOutside += 1
                    )
                )
            )

            logLines = #()
            append logLines ("Maps relinked / fixed : " + fixedCount as string)
            append logLines ("Still missing / relative : " + stillMissing as string)
            if stillOutside > 0 do append logLines ("Still outside project  : " + stillOutside as string)
            append logLines ""

            if stillMissing == 0 then (
                if stillOutside > 0 then (
                    append logLines "No missing maps, but some remain outside."
                    btn_main_s3.text = "MAPS OK\n⚠ CHECK PATHS"
                ) else (
                    append logLines "All maps resolved and in project !"
                    btn_main_s3.text = "ALL MAPS\nOK ✓"
                )
                step3_state = 4
                btn_main_s3.enabled = false
            ) else (
                append logLines "--- Still missing ---"
                for b in bitmapList do (
                    local st = checkBitmapStatus b
                    if st == "MISSING" or st == "RELATIVE" then (
                        local fname = ""
                        try( fname = b.filename )catch()
                        append logLines ("  x " + filenameFromPath fname)
                    )
                )
                step3_state = 3 
            )
            
            lst_log_s3.items = logLines
            showCurrentStepUI()
        )

        fn completeStep3 = ( 
            stepStates[3] = 1; updateChecklistUI()
            switchStep 4
        )

        -- ===========================================================
        -- METHODES ETAPES 4 à 9 
        -- ===========================================================
        fn hasDiffScale obj eps:0.005 = ( local s = obj.scale; (abs(s.x - s.y) > eps) or (abs(s.x - s.z) > eps) or (abs(s.y - s.z) > eps) )
        fn rPivot = (
            local diffScaleObjs = #()
            for o in objects do ( if hasDiffScale o then append diffScaleObjs o else ( CenterPivot o; WorldAlignPivot o; o.pivot = [o.center.x,o.center.y,o.min.z] ) )
            if diffScaleObjs.count > 0 do ( for o in diffScaleObjs do ( ResetXForm o; CenterPivot o; WorldAlignPivot o; o.pivot = [o.center.x, o.center.y, o.min.z] ) )
            lst_log_s4.items = #("Pivots correctement reset.")
        )
        fn rGrpPivot = ( max select none; max select all; local tempGROUP = group selection; rPivot() )

        fn wColor = (   
            local r = random 0 255; local g = random 0 255; local b = random 0 255
            local changedCount = 0
            for o in objects do ( if o.wirecolor == (color 0 0 0) then ( o.wirecolor = (color r g b); changedCount += 1 ) )
            if changedCount > 0 then lst_log_s5.items = #("Validé : " + (changedCount as string) + " wirecolors changés.")
            else lst_log_s5.items = #("Validé : Aucun wirecolor noir trouvé.")
        )

        fn listAllLayers = (
            local layerNames = #()
            for i = 0 to (LayerManager.count - 1) do append layerNames (LayerManager.getLayer i).name
            lst_log_s6.items = layerNames
        )

        fn getPrefix = (
            local n = getFilenameFile maxFileName
            n = substituteString n "_corona" ""
            n = substituteString n "_vray" ""
            n = substituteString n "-corona" ""
            n = substituteString n "-vray" ""
            return n
        )
        
        fn updateNameList = (
            local arr = for o in objects collect o.name
            lst_names_s7.items = sort arr
        )
        
        fn renameItemFromList itemName = (
            local theObj = getNodeByName itemName
            if theObj != undefined do (
                local renameDialog = dotNetObject "MaxCustomControls.RenameInstanceDialog" (theObj.name as string)
                renameDialog.Text = "Rename object"
                local dialogResult = renameDialog.Showmodal()
                if dotnet.compareenums dialogResult ((dotnetclass "System.Windows.Forms.DialogResult").OK) then (
                    local newName = renameDialog.InstanceName as string
                    if newName != "" do ( undo "Rename" on theObj.name = newName; updateNameList() )
                )
            )
        )

        fn checkPreviewImage = (
            local imgfolder = maxFilePath
            local imgbaseName = getFilenameFile maxFileName
            local imgextensions = #(".jpg", ".jpeg", ".png", ".bmp")
            local foundImage = false
            
            for ext in imgextensions where not foundImage do (
                if doesFileExist (imgfolder + imgbaseName + ext) do foundImage = true
            )
            
            if foundImage then (
                lst_log_s8.items = #("✔ Image de prévisualisation trouvée.")
                btn_prev_fix_s8.visible = false
                return true
            ) else (
                lst_log_s8.items = #("⚠ Aucune image trouvée avec le nom : " + imgbaseName)
                btn_prev_fix_s8.visible = true
                return false
            )
        )

        fn initDotNetCombobox ctrl = (
            try(
                ctrl.Items.Clear()
                ctrl.AutoCompleteMode = (dotNetClass "System.Windows.Forms.AutoCompleteMode").SuggestAppend
                ctrl.AutoCompleteSource = (dotNetClass "System.Windows.Forms.AutoCompleteSource").ListItems
                ctrl.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDown
                ctrl.BackColor = (dotNetClass "System.Drawing.Color").fromArgb 68 68 68
                ctrl.ForeColor = (dotNetClass "System.Drawing.Color").fromArgb 230 230 230
                ctrl.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").Flat
                ctrl.Text = "" 
            )catch()
        )

        fn getAiKeywords = (
            local imgfolder = maxFilePath
            local imgbaseName = getFilenameFile maxFileName
            local imgextensions = #(".jpg", ".jpeg", ".png")
            local imagePath = undefined
            for ext in imgextensions do ( if doesFileExist (imgfolder + imgbaseName + ext) do imagePath = (imgfolder + imgbaseName + ext) )
            
            if imagePath == undefined then ( messageBox "No matching image found (jpg/png) for AI."; return #() )
            
            local pythonExe = "C:\\Users\\" + sysInfo.username + "\\AppData\\Local\\Microsoft\\WindowsApps\\python.exe"
            local scriptDir = "C:\\Users\\" + sysInfo.username + "\\Documents\\3ds Max 2024\\Scripts\\"
            local pythonScript = scriptDir + "_MyTools_Files_MapSearch.py"
            local keywordsFile = scriptDir + "MaxStack-MaxStack_FileChecker_Keywords_List.txt"
            local tempFile = getDir #temp + "\\object_list.txt"
            
            if not (doesFileExist pythonExe) then ( messageBox "Python introuvable"; return #() )
            if doesFileExist tempFile then deleteFile tempFile
            
            local args = "/c \"\"" + pythonExe + "\" \"" + pythonScript + "\" \"" + imagePath + "\" \"" + tempFile + "\" \"" + keywordsFile + "\"\""
            local p = dotNetObject "System.Diagnostics.Process"
            p.StartInfo.FileName = "cmd.exe"; p.StartInfo.Arguments = args; p.StartInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden; p.StartInfo.UseShellExecute = false; p.StartInfo.CreateNoWindow = true
            p.Start(); p.WaitForExit()
            
            local keywordsFound = #()
            if doesFileExist tempFile then ( local f = openFile tempFile; while not eof f do ( local line = readLine f; if (trimLeft (trimRight line)) != "" then append keywordsFound line ); close f; return keywordsFound )
            else ( messageBox "Erreur AI"; return #() )
        )

        fn initStep9Keywords = (
            local kFields = #(cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15)
            local allCBX = #(cbx_cat, cbx_subcat)
            join allCBX kFields
            
            for c in allCBX do initDotNetCombobox c
            
            -- Categories
            local catNames = #()
            for d in database do append catNames d.catName
            sort catNames
            fillComboBox cbx_cat catNames

            -- Keywords Cache depuis le Splash Screen
            if netKeywords_Cache != undefined do (
                for kf in kFields do (
                    kf.BeginUpdate()
                    kf.Items.AddRange netKeywords_Cache
                    kf.EndUpdate()
                )
            )

            -- Auto-remplissage via le fichier OK ou les dossiers
            if maxFileName != "" do (
                local txt_filename = (maxFilePath+maxFileName+"_CHECKED_OK.txt")
                local fileExists = doesFileExist txt_filename
                local loaded_cat = ""; local loaded_subcat = ""; local loaded_keywords = #()
                
                if fileExists then (
                    local f = openFile txt_filename
                    while not eof f do (
                        local line = trimLeft (trimRight (readLine f))
                        if line != "" do (
                            if (matchPattern line pattern:"--*") then loaded_subcat = substring line 3 -1
                            else if (matchPattern line pattern:"-*") then loaded_cat = substring line 2 -1
                            else if line != (sysInfo.username as string) then append loaded_keywords line
                        )
                    )
                    close f
                    
                    if loaded_cat != "" do ( 
                        cbx_cat.Text = loaded_cat
                        local foundSubs = #()
                        for d in database do (
                            if (stricmp d.catName loaded_cat) == 0 do (
                                for s in d.subcats do append foundSubs s; sort foundSubs; exit
                            )
                        )
                        fillComboBox cbx_subcat foundSubs
                    )
                    if loaded_subcat != "" do cbx_subcat.Text = loaded_subcat
                    local idx = 1
                    for k in loaded_keywords do ( if idx <= 15 do ( kFields[idx].Text = k; idx += 1 ) )
                ) else (
                    local searchPathFolders = filterString maxFilePath "\\"
					if searchPathFolders.count >= 3 do (
						local folderCat = resolveFolderAlias searchPathFolders[3]
                        for d in database do ( if (d.catName == folderCat) or ((d.catName + "s") == folderCat) do ( 
                            cbx_cat.Text = d.catName; 
                            local subs = #()
                            for s in d.subcats do append subs s
                            sort subs
                            fillComboBox cbx_subcat subs
                            exit 
                        ) )
                    )
                    if searchPathFolders.count >= 4 do (
						local folderSub = resolveFolderAlias searchPathFolders[4]
						local currentSubs = #()
						if cbx_cat.Text != "" then (
							for d in database do (
								if (stricmp d.catName cbx_cat.Text == 0) do (
									for s in d.subcats do append currentSubs s
								)
							)
						) else (
							for d in database do join currentSubs d.subcats
						)
						if currentSubs != undefined and currentSubs.count > 0 do (
							for s in currentSubs do (
								if (stricmp folderSub s == 0) or (stricmp folderSub (s+"s") == 0) or (matchPattern folderSub pattern:(s+"*") ignoreCase:true) do (
									cbx_subcat.Text = s; exit
								)
							)
						)
					)
                    if searchPathFolders.count >= 3 and (stricmp searchPathFolders[3] "BRANDS" == 0) do ( for f in kFields do ( if f.Text == "" do ( f.Text = "Brands"; exit ) ) )
                    if searchPathFolders.count >= 3 and (stricmp searchPathFolders[3] "dimensiva" == 0) do ( for f in kFields do ( if f.Text == "" do ( f.Text = "Dimensiva"; exit ) ) )
                )
            )
        )

        -- ===========================================================
        -- CASCADE D'AUTO-CHECK (La magie du passage automatique)
        -- ===========================================================
        fn switchStep newStep =
        (
            local isMovingForward = (newStep > currentStep)
            
            if isMovingForward then (
                local autoChecking = true
                while autoChecking do (
                    autoChecking = false
                    
                    if newStep == 3 and stepStates[3] == 0 then (
                        local mapsOk = doStep3_Scan()
                        if mapsOk then ( stepStates[3] = 1; newStep = 4; autoChecking = true )
                    )
                    if newStep == 5 and stepStates[5] == 0 then (
                        local hasBlack = false
                        for o in objects where o.wirecolor == (color 0 0 0) do ( hasBlack = true; exit )
                        if not hasBlack then ( stepStates[5] = 1; newStep = 6; autoChecking = true )
                    )
                    if newStep == 6 and stepStates[6] == 0 then (
                        if LayerManager.count <= 1 then ( stepStates[6] = 1; newStep = 7; autoChecking = true )
                    )
                    if newStep == 8 and stepStates[8] == 0 then (
                        local hasImg = checkPreviewImage()
                        if hasImg then ( stepStates[8] = 1; newStep = 9; autoChecking = true )
                    )
                )
            )

            currentStep = newStep
            updateChecklistUI()
            showCurrentStepUI()
            
            if currentStep == 1 and stepStates[1] == 0 do (
                lst_log_s1.items = #("Cliquez sur le bouton pour analyser la scène et exécuter le nettoyage automatique (Clean Reset).")
            )
            if currentStep == 2 and stepStates[2] == 0 do doCheckFilename()
            if currentStep == 3 and stepStates[3] == 0 do doStep3_Scan()
            if currentStep == 4 do lst_log_s4.items = #("⚠ ATTENTION :","Vérifier manuellement certains pivots comme les luminaires (pivot = plafond) et cadres (pivot = centre dos / mur).","\n","Cliquez sur l'action à effectuer.")
            if currentStep == 6 do (
                if stepStates[6] == 1 then lst_log_s6.items = #("✔ Seul le layer 0 est présent.", "Étape auto-validée.")
                else listAllLayers()
            )
            if currentStep == 7 do ( edt_n_pref.text = getPrefix(); updateNameList() )
            if currentStep == 8 do checkPreviewImage()
        )

        -- ===========================================================
        -- INITIALISATION ET EVENTS DE NAVIGATION MAIN
        -- ===========================================================
        on rlMasterChecker open do ( 
            -- ON MASQUE TOUT IMMÉDIATEMENT POUR ÉVITER LES OVERLAPS UI
            hideAllUI()
            
            -- ON INITIALISE TOUS LES DOTNET ICI POUR ASSURER LA CRÉATION DU HANDLE
            initStep9Keywords() 
            
            edt_before_s2.text = ""
            edt_after_s2.text  = ""
            
            lbl_reload.visible = false
            switchStep 1 
        )

        on btn_next pressed do ( if currentStep < 9 do switchStep (currentStep + 1) )
        on btn_prev pressed do ( if currentStep > 1 do switchStep (currentStep - 1) )

        -- EVENTS S1 (CORONA & RESET)
        on btn_main_s1 pressed do ( doCheckCorona() )
        on btn_recheck_s1 pressed do ( doCheckCorona() )
        
        on btn_converter_s1 pressed do (
            try ( actionMan.executeAction 572340868 "7" ) catch ( messageBox "Impossible d'ouvrir le Corona Converter.\nVérifiez que Corona est bien installé." title:"Erreur MaxStack" )
        )
        
        on btn_done_s1 pressed do (
            local currRend = classOf renderers.current as string
            local isCorona = matchPattern currRend pattern:"*Corona*" ignoreCase:true
            if not isCorona then (
                local warningLines = lst_log_s1.items
                append warningLines "---"
                append warningLines "⚠ Validé manuellement sans conversion au moteur Corona."
                lst_log_s1.items = warningLines
                completeStep1()
            ) else (
                lst_log_s1.items = #("✔ Matériaux nettoyés et moteur validé.", "Lancement du Clean Reset...")
                doCleanReset()
            )
        )

        -- EVENTS S2 (FILENAME)
        on btn_main_s2 pressed do ( if currentStep == 2 and step2_state == 1 do doCheckFilename() )
        
        on btn_confirm_s2 pressed do (
            if currentStep == 2 and step2_state == 2 then (
                local fullPath = maxFilePath + maxFileName
                local result   = doRenameOnDisk fullPath cleanedName

                if result[1] == true then (
                    if result[2] == "unchanged" then lst_log_s2.items = #("File was already correctly named.", "Nothing changed.")
                    else (
                        local newFull = result[2]
                        local reloaded = loadMaxFile newFull useFileUnits:true quiet:true
                        if reloaded then lst_log_s2.items = #("✔  File renamed successfully.", "", "New name : " + (getFilenameFile newFull) + ".max", "Path     : " + (getFilenamePath newFull), "", "File reloaded in 3ds Max.")
                        else lst_log_s2.items = #("✔  File renamed on disk.", "⚠  Could not auto-reload — please reopen manually:", newFull)
                    )
                    completeStep2()
                ) else lst_log_s2.items = #("ERROR renaming file :", result[2])
            )
        )

        -- EVENTS S3 (MAPS)
        on btn_main_s3 pressed do (
            if step3_state == 1 then doStep3_Scan()
            else if step3_state == 2 then doStep3_Relink()
        )
        on btn_force_s3 pressed do ( ATSOps.visible = true; atsops.refresh() )
        
        on btn_remove_missing_s3 pressed do (
            undo "Remove Missing Maps" on (
                collectAllBitmaps()
                local count = 0
                for b in bitmapList do (
                    if (checkBitmapStatus b) == "MISSING" or (checkBitmapStatus b) == "RELATIVE" do (
                        try( b.filename = ""; count += 1 )catch()
                    )
                )
                messageBox ((count as string) + " bitmaps missing effacés de la scène.") title:"Remove Missing"
                doStep3_Scan()
            )
        )
        
        on btn_recheck_s3 pressed do ( doStep3_Scan() )
        
        on btn_done_s3 pressed do ( completeStep3() )

        -- EVENTS S4 (PIVOTS)
        on btn_piv_each_s4 pressed do ( undo "Pivot Each" on rPivot() )
        on btn_piv_grp_s4 pressed do ( undo "Pivot Group" on rGrpPivot() )
        on btn_done_s4 pressed do ( stepStates[4] = 1; updateChecklistUI(); switchStep 5 )

        -- EVENTS S5 (WIRECOLOR)
        on btn_wire_s5 pressed do ( undo "Wirecolor" on wColor() )
        on btn_done_s5 pressed do ( stepStates[5] = 1; updateChecklistUI(); switchStep 6 )

        -- EVENTS S6 (LAYERS)
        on btn_lay_fix_s6 pressed do (
            undo "Fix Layers" on (
                local layer0 = layermanager.getLayerFromName "0"
                for o in objects do if o.layer.name != "0" do layer0.addNode o
                local i = LayerManager.count - 1
                while (i > 0) do (
                    local lyr = LayerManager.getLayer i
                    if (lyr.name != "0" and lyr.getNumChildren() == 0) do LayerManager.deleteLayerByName (lyr.name as string)
                    i -= 1
                )
                listAllLayers()
            )
        )
        on btn_done_s6 pressed do ( stepStates[6] = 1; updateChecklistUI(); switchStep 7 )

        -- EVENTS S7 (NAMES)
        on btn_n_all pressed do (
            local pfx = edt_n_pref.text; local base = edt_n_base.text
            undo "Name All" on ( for o in objects do ( if base != "" then o.name = pfx + "_" + base else if (findString o.name pfx) == undefined do o.name = pfx + "_" + o.name ) )
            updateNameList()
        )
        
        on btn_n_sel pressed do (
            local pfx = edt_n_pref.text; local base = edt_n_base.text
            local targetObjs = #()
            
            if lst_names_s7.selection.isEmpty == false then (
                local selIndices = lst_names_s7.selection as array
                for i in selIndices do (
                    local obj = getNodeByName lst_names_s7.items[i]
                    if obj != undefined do append targetObjs obj
                )
            ) else (
                targetObjs = selection as array
            )
            
            if targetObjs.count > 0 do (
                undo "Name Selected" on (
                    for o in targetObjs do (
                        if base != "" then o.name = pfx + "_" + base 
                        else if (findString o.name pfx) == undefined do o.name = pfx + "_" + o.name 
                    )
                )
                updateNameList()
            )
        )
        
        on btn_n_grp pressed do (
            local pfx = edt_n_pref.text; local Selmain = #()
            for o in objects do ( if o.parent == undefined do append Selmain o )
            undo "Name Group" on ( if Selmain.count >= 2 then ( for s in Selmain do s.name = pfx + "_" + s.name ) else ( for s in Selmain do s.name = pfx ) )
            updateNameList()
        )
        
        on btn_n_replace pressed do (
            local sText = edt_n_search.text; local rText = edt_n_repl.text
            if sText != "" do ( 
                undo "Search Replace" on ( 
                    for o in objects do (
                        if matchPattern o.name pattern:("*"+sText+"*") do o.name = substituteString o.name sText rText 
                    ) 
                )
                updateNameList() 
            )
        )
        
        on lst_names_s7 doubleClicked idx do ( if idx > 0 do renameItemFromList lst_names_s7.items[idx] )
        on btn_done_s7 pressed do ( stepStates[7] = 1; updateChecklistUI(); switchStep 8 )

        -- EVENTS S8 (PREVIEW)
        on btn_prev_fix_s8 pressed do (
            local imgfolder = maxFilePath
            local checkFiles = #()
            
            for ext in #(".jpg", ".jpeg", ".png", ".bmp") do (
                join checkFiles (getFiles (imgfolder + "*" + ext))
            )
            
            if checkFiles.count == 0 then (
                messageBox "Aucune image trouvée dans ce dossier." title:"Preview image"
            ) else (
                createDialog rl_selectImage
            )
        )
        on btn_done_s8 pressed do ( stepStates[8] = 1; updateChecklistUI(); switchStep 9 )

        -- EVENTS S9 (KEYWORDS)
        on cbx_cat SelectedIndexChanged s e do (
            local subs = #()
            for d in database do (
                if (stricmp d.catName s.Text) == 0 do (
                    for c in d.subcats do append subs c
                    sort subs
                    exit
                )
            )
            fillComboBox cbx_subcat subs
        )
        
        on btn_ai_s9 pressed do (
            local aiResults = getAiKeywords()
            if aiResults.count > 0 do (
                local kFields = #(cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15)
                local idx = 1
                for f in kFields do ( if f.Text == "" and idx <= aiResults.count do ( f.Text = aiResults[idx]; idx += 1 ) )
            )
        )
        
        fn doSaveOkFile silent:false = (
			if cbx_cat.Text == "" then (
				messageBox "⚠ Please select a Category before saving." title:"Save OK File"
				return false
			)
			if cbx_subcat.Text == "" then (
				messageBox "⚠ Please select a Subcategory before saving." title:"Save OK File"
				return false
			)
			
			local txt_filename = (maxFilePath+maxFileName+"_CHECKED_OK.txt")
			local txt_file = createfile txt_filename
			format ("-"+(cbx_cat.Text)+"\n") to:txt_file
			format ("--"+(cbx_subcat.Text)+"\n") to:txt_file
			local kFields = #(cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15)
			for f in kFields do ( if f.Text != "" do format (f.Text + "\n") to:txt_file )
			format (sysInfo.username as string) to:txt_file
			close txt_file
			stepStates[9] = 1; updateChecklistUI()
			if not silent do messageBox "OK File Generated!" title:"Done"
			return true
		)

		on btn_done_s9 pressed do ( doSaveOkFile silent:false )
        
        on btn_final_validate_s9 pressed do (
			-- Sauvegarde du OK file (avec validation cat/subcat intégrée)
			local saved = doSaveOkFile silent:true
			if not saved do return false
			
			-- Sauvegarde automatique de la scène max
			if maxFilePath != "" do saveMaxFile (maxFilePath + maxFileName) quiet:true
			
			-- Validation de la présence de l'image
			local imgfolder = maxFilePath
			local imgbaseName = getFilenameFile maxFileName
			local imgextensions = #(".jpg", ".jpeg", ".png", ".bmp")
			local hasImg = false
			for ext in imgextensions where not hasImg do ( if doesFileExist (imgfolder + imgbaseName + ext) do hasImg = true )
			
			if not hasImg then (
				messageBox "⚠ Validation finale impossible !\n\nL'image de preview est introuvable.\nVeuillez vérifier qu'elle est bien présente." title:"Validation Finale"
			) else (
				local res = yesNoCancelBox "Le fichier a été enregistré et vérifié avec succès !\n\nVoulez-vous fermer 3ds Max ?\n\nOui = Fermer 3ds Max\nNon = Laisser ouvert" title:"Validation Finale"
				if res == #yes then (
					quitMax #noPrompt
				) else (
					-- LOAD FOLDER ALIASES CSV
					local aliasCsvPath = "L:\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\MaxStack-MaxStack_FileChecker_FolderAliases.csv"
					local folderAliases = #()  -- array de paires #(rawFolder, resolvedName)
					if doesFileExist aliasCsvPath do (
						local fAlias = openFile aliasCsvPath
						while not eof fAlias do (
							local parts = filterString (readLine fAlias) ";"
							if parts.count >= 2 do (
								local raw      = trimLeft (trimRight parts[1])
								local resolved = trimLeft (trimRight parts[2])
								if raw != "" and resolved != "" do append folderAliases #(raw, resolved)
							)
						)
						close fAlias
					)

					-- Ferme le Splash et ouvre la fenêtre principale
					try(DestroyDialog rlMasterChecker) catch()
				)
			)
		)
    )

    -- Le script démarre par l'ouverture du Splash Screen qui, une fois fini, ouvrira rlMasterChecker
    rl_Splash()
)