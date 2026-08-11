/*
================================================================================
Script Name: Iconia_MergeArchiveSelection
Category: Iconia
Description: Menu d'import des archives du projet en cours.
================================================================================
*/
macroScript Iconia_MergeArchiveSelection
category:"Iconia"
buttonText:"Import Archive"
tooltip:"Open a menu with previews to import archive file"
(
try(destroyDialog ArchiveBrowser)catch()

rollout ArchiveBrowser "Browser d'Archives" width:920 height:1000
(
    -- Utilisation d'un FlowLayoutPanel .NET pour gérer une grille dynamique d'images
    dotNetControl flp "System.Windows.Forms.FlowLayoutPanel" width:900 height:980 pos:[10,10]

    -- Fonction déclenchée au clic sur une miniature
    fn onThumbnailClicked s e =
    (
        local imgPath = s.Tag
        local maxFile = (getFilenamePath imgPath) + (getFilenameFile imgPath) + ".max"

        if doesFileExist maxFile then
        (
            if queryBox ("Voulez-vous merger le fichier suivant dans la scène ?\n\n" + (getFilenameFile maxFile)) title:"Confirmation de Merge" do
            (
                mergeMAXFile maxFile #select #useMergedMtlDups #alwaysReparent
                print ("Merché avec succès : " + maxFile)
            )
        )
        else
        (
            messageBox "Aucun fichier .max correspondant n'a été trouvé pour cette image." title:"Erreur de Merge"
        )
    )

    on ArchiveBrowser open do
    (
        -- Configuration du panneau
        flp.AutoScroll = true
        flp.WrapContents = true
        flp.BackColor = (dotNetClass "System.Drawing.Color").FromArgb 40 40 40

        -- Détermination du chemin de base
        local basePath = maxFilePath
        if basePath == "" do basePath = pathConfig.getCurrentProjectFolder() + "\\"	
        
        local archivePath = undefined
    
	-- Vérification de l'existence des sous-dossiers
	local dir_array = (GetDirectories (maxFilePath+"/*"))
	for d in dir_array do
	(
		local pathParts = filterString d "\\"
		local lastFolder = pathParts[pathParts.count]
		if matchPattern lastFolder pattern:"*archive*" then (archivePath = (maxFilePath + lastFolder + "\\"))
	)

        if archivePath != undefined then
        (
            -- Récupération des JPG/JPEG
            local jpgFiles = (getFiles (archivePath + "*.jpg"))
            join jpgFiles (getFiles (archivePath + "*.jpeg"))

            if jpgFiles.count == 0 do
            (
                messageBox "Le dossier d'archive a été trouvé, mais il ne contient aucune image .jpg ou .jpeg." title:"Dossier vide"
                return false
            )

            local imgClass = dotNetClass "System.Drawing.Image"

            for i = jpgFiles.count to 1 by -1 do
            (
                local f = jpgFiles[i]
                -- Chargement via File.OpenRead pour eviter le probleme de constructeur FileStream
                local fs = (dotNetClass "System.IO.File").OpenRead f
                local loadedImg = imgClass.FromStream fs
                fs.Close()

                -- Création de la PictureBox
                local pb = dotNetObject "System.Windows.Forms.PictureBox"
                pb.Width = 1300
                pb.Height = 650 -- Format 2:1
                pb.SizeMode = (dotNetClass "System.Windows.Forms.PictureBoxSizeMode").Zoom
                pb.Image = loadedImg
                pb.Tag = f -- On stocke le chemin de l'image dans le Tag pour le récupérer au clic
                pb.Cursor = (dotNetClass "System.Windows.Forms.Cursors").Hand
                
                -- Ajout d'une marge pour l'esthétique
                pb.Margin = dotNetObject "System.Windows.Forms.Padding" 5

                -- Ajout de l'événement clic
                dotNet.addEventHandler pb "Click" onThumbnailClicked

                -- Ajout au panneau
                flp.Controls.Add pb
            )
        )
        else
        (
            messageBox "Impossible de trouver le sous-dossier 'Archive' dans le répertoire courant." title:"Dossier introuvable"
        )
    )
	on ArchiveBrowser close do
	(
		for c in flp.Controls do
		(
			try(dotNet.removeEventHandler c "Click" onThumbnailClicked)catch()
			try(if c.Image != undefined do c.Image.Dispose())catch()
			try(c.Dispose())catch()
		)
		flp.Controls.Clear()
	)
)

createDialog ArchiveBrowser
)