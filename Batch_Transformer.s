/* 
DigitalMicrograph Script: Batch Image Transformer UI
A UI providing various functions to process all images in the current workspace.
The table below lists the supported data types for each operation:
					Binary	|	Integer	|	Real	|	Complex	|	RGB
Flip Horizontal		Y		|	Y		|	Y		|	Y		|	Y
Flip Vertical		Y		|	Y		|	Y		|	Y		|	Y
Rotate Right		N		|	Y		|	Y		|	Y		|	Y
Rotate Left			N		|	Y		|	Y		|	Y		|	Y
Rebin				N		|	Y		|	Y		|	Y		|	Y
Sharpen				Y		|	Y		|	Y		|	Y		|	Y
Smooth				Y		|	Y		|	Y		|	Y		|	Y
Laplacian			Y		|	Y		|	Y		|	Y		|	Y
Sobel				Y		|	Y		|	Y		|	Y		|	Y
Non-Linear Filter	Y		|	Y		|	Y		|	N		|	N
FFT					Y		|	Y		|	Y		|	Y		|	Y
Binned FFT			Y		|	Y		|	Y		|	Y		|	Y
Autocorrelation		N		|	Y		|	Y		|	N		|	N

MIT License, Copyright (c) 2026 Meco
Version: 1.0.0
Source: https://github.com/lmengchia
*/

class BatchTransformerUI : UIFrame {
    
	TagGroup CreateRebin(Object self) {
		TagGroup DLG, DLGItems
		DLG = DLGCreateDialog( "Rebin settings", DLGItems )

		TagGroup radio1tg = DLGCreateRadioList( 2 )
		radio1tg.DLGAddRadioItem( "Re-bin by 2", 2 )
		radio1tg.DLGAddRadioItem( "Re-bin by 4", 4 )
		radio1tg.DLGAddRadioItem( "Re-bin by 8", 8 )
		
		DLGitems.DLGAddElement( DLGCreateLabel( "Please select an option:" ) )        
		DLGitems.DLGAddElement( radio1tg )        
		
		if ( !Alloc( UIframe ).Init( DLG ).Pose() )
			Throw( "User abort." )
		
		number selectedValue = radio1tg.DLGGetValue()
		SetPersistentNumberNote( "MySettings:RadioValue", selectedValue )
		
		Return DLG
	}
	
	TagGroup CreateNonLinearFilter(Object self) {
		TagGroup DLG, DLGItems
		DLG = DLGCreateDialog( "Non-Linear Filter", DLGItems )
		
		TagGroup type1tg = DLGCreateChoice( 0 )
		type1tg.DLGAddChoiceItemEntry( "Median" )
		type1tg.DLGAddChoiceItemEntry( "Minimum" )
		type1tg.DLGAddChoiceItemEntry( "Maximum" )
		type1tg.DLGAddChoiceItemEntry( "Range" )
		type1tg.DLGAddChoiceItemEntry( "Midpoint" )
		DLGitems.DLGAddElement( DLGCreateLabel( "Type:" ).DLGAnchor("West") )        
		DLGitems.DLGAddElement( type1tg.DLGAnchor("West") )
		
		TagGroup windowSizeltg = DLGCreateChoice( 0 )
		windowSizeltg.DLGAddChoiceItemEntry( "3" )
		windowSizeltg.DLGAddChoiceItemEntry( "5" )
		windowSizeltg.DLGAddChoiceItemEntry( "7" )
		windowSizeltg.DLGAddChoiceItemEntry( "9" )
		windowSizeltg.DLGAddChoiceItemEntry( "11" )
		DLGitems.DLGAddElement( DLGCreateLabel( "Window Size:" ).DLGAnchor("West") )        
		DLGitems.DLGAddElement( windowSizeltg.DLGAnchor("West") )
		
		TagGroup windowShape1tg = DLGCreateChoice( 0 )
		windowShape1tg.DLGAddChoiceItemEntry( "Horizontal" )
		windowShape1tg.DLGAddChoiceItemEntry( "Vertical" )
		windowShape1tg.DLGAddChoiceItemEntry( "Cross" )
		windowShape1tg.DLGAddChoiceItemEntry( "Entire" )
		DLGitems.DLGAddElement( DLGCreateLabel( "Window Shape:" ).DLGAnchor("West") )        
		DLGitems.DLGAddElement( windowShape1tg.DLGAnchor("West") )
   		
		if ( !Alloc( UIframe ).Init( DLG ).Pose() )
			Throw( "User abort." )
		
		number selectedType = type1tg.DLGGetValue()
		number selectedWindowSize = windowSizeltg.DLGGetValue()
		number selectedWindowShape = windowShape1tg.DLGGetValue()
		SetPersistentNumberNote( "MySettings:TypeValue", selectedType )
		SetPersistentNumberNote( "MySettings:WindowSizeValue", selectedWindowSize )
		SetPersistentNumberNote( "MySettings:WindowShapeValue", selectedWindowShape )
		
		Return DLG
	}
    
    void ProcessImages(object self, string action) {
        number numDocs = CountImageDocuments();
        number reBinValue
        number typeValue, windowSizeValue, windowShapeValue;
        if (numDocs == 0) {
            OKDialog("No images on the current workspace.");
            return;
        }

		if (action == "Rebin") {
			self.CreateRebin()
			if ( GetPersistentNumberNote( "MySettings:RadioValue", reBinValue ) )
				Result( "Selected rebin value:" + reBinValue + "\n" )
			else
				return;
		}
		if (action == "Non-Linear Filter") {
			self.CreateNonLinearFilter()
			if ( GetPersistentNumberNote( "MySettings:TypeValue", typeValue ) )
				Result( "Selected typeValue:" + typeValue + "\n" )
			if ( GetPersistentNumberNote( "MySettings:WindowSizeValue", windowSizeValue ) )
				Result( "Selected windowSizeValue:" + windowSizeValue + "\n" )
			if ( GetPersistentNumberNote( "MySettings:WindowShapeValue", windowShapeValue ) )
				Result( "Selected windowShapeValue:" + windowShapeValue + "\n" )
		}

        TagGroup idList = NewTagList();
        for (number i = 0; i < numDocs; i++) {
            ImageDocument doc = GetImageDocument(i);
            if (doc.ImageDocumentIsValid()) {
                idList.TagGroupInsertTagAsUInt32(0xFFFFFFFF, doc.ImageDocumentGetID());
            }
        }

        number originalWorkspace = WorkspaceGetActive();
        string baseWkspName = WorkspaceGetName(originalWorkspace);
        string newWorkspaceName = baseWkspName + "_Processed_" + action;
        number targetIndex = -1;
        number wkspCount = WorkspaceGetCount();
        
        for (number i = 0; i < wkspCount; i++) {
            if (WorkspaceGetName(i) == newWorkspaceName) {
                targetIndex = i;
                break;
            }
        }

         if (targetIndex == -1) {
            targetIndex = WorkspaceAdd(wkspCount);
            WorkspaceSetName(targetIndex, newWorkspaceName);
        }
        
        WorkspaceSetActive(targetIndex);

        number count = idList.TagGroupCountTags();
        number successCount = 0, failCount = 0;
        for (number i = 0; i < count; i++) {
            number docID;
            number processed = 0;
            idList.TagGroupGetIndexedTagAsUInt32(i, docID);
            
            ImageDocument originalDoc = GetImageDocumentByID(docID);
            if (!originalDoc.ImageDocumentIsValid()) continue;

            image img := originalDoc.ImageDocumentGetRootImage();
            if (!img.ImageIsValid()) continue;
            
            ImageDocument clonedDoc = originalDoc.ImageDocumentClone( 1 );
            image newImg := clonedDoc.ImageDocumentGetRootImage();
            string newName;

            if (action == "FlipH" || action == "FlipV" || action == "RotR" || action == "RotL") {
                if (action == "FlipH") {
                    newImg.FlipHorizontal();
                    processed = 1;
                } else if (action == "FlipV") {
                    newImg.FlipVertical();
                    processed = 1;
                } else if (action == "RotR" && !ImageIsDataTypeBinary( img )) {
                    newImg.RotateRight();
                    processed = 1;
                } else if (action == "RotL" && !ImageIsDataTypeBinary( img )) {
                    newImg.RotateLeft();
                    processed = 1;
                }
                newName = img.GetName() + "_" + action
            } 
            else if (action == "FFT" || action == "BinnedFFT") {
                newImg.ConvertToComplex()
                if (action == "FFT") {
					newImg := FFT (newImg)
                } else if (action == "BinnedFFT") {
					RebinInPlace( newImg, 2, 2)
					newImg := FFT (newImg) * 4
                }
                if (!ImageIsDataTypeComplex( img )) { newImg.ConvertToPackedComplex(); }
                processed = 1;
                newName = img.GetName() + "_" + action
            }
            else if (action == "Rebin" && !ImageIsDataTypeBinary( img ) ) {
                RebinInPlace( newImg, reBinValue, reBinValue)
                newName = img.GetName() + "_" + action + "by" + reBinValue
                processed = 1;
            }
            else if (action == "Sharpen") {
                newImg := newImg.SharpenFilter()
                newName = img.GetName() + "_" + action
                processed = 1;
            }
            else if (action == "Smooth") {
                newImg := newImg.SmoothFilter()
                newName = img.GetName() + "_" + action
                processed = 1;
            }
            else if (action == "Laplacian") {
                newImg := newImg.LaplaceFilter()
                newName = img.GetName() + "_" + action
                processed = 1;
            }
            else if (action == "Sobel") {
                newImg := newImg.SobelFilter()
                newName = img.GetName() + "_" + action
                processed = 1;
            }
            else if (action == "Non-Linear Filter" && !ImageIsDataTypeComplex( img ) && !ImageIsDataTypeRGB( img )) {
                newImg := RankFilter(newImg, typeValue, windowShapeValue, windowSizeValue + 1)
                newName = img.GetName() + "_" + action
                processed = 1;
            }
            else if (action == "Autocorrelation" && !ImageIsDataTypeBinary( img ) && !ImageIsDataTypeComplex( img ) && !ImageIsDataTypeRGB( img )) {
                newImg := newImg.AutoCorrelation()
                newName = img.GetName() + "_" + action
                processed = 1;
            }
        
			if (processed == 1) {
				successCount += 1;
				newImg.SetName(newName);
				clonedDoc.ImageDocumentShow();
				result( action + " process for " + img.GetName() + " is completed" + "\n");
			} else {
				failCount += 1;
				result( action + " process for " + img.GetName() + " is unsupported!" + "\n");
			}
		
        }
        
        result( "Total " + successCount + " images are processed " + action + "\n");	
		if ( !failCount == 0) { result( "Total " + failCount + " images are unsupported " + action + "\n"); }	
        
    }

    void OnFlipHorizontal( object self ) { self.ProcessImages("FlipH"); }
    void OnFlipVertical( object self ) { self.ProcessImages("FlipV"); }
    void OnRotateRight( object self ) { self.ProcessImages("RotR"); }
    void OnRotateLeft( object self ) { self.ProcessImages("RotL"); }
    void OnFFT( object self ) { self.ProcessImages("FFT"); }
    void OnBinnedFFT( object self ) { self.ProcessImages("BinnedFFT"); }
    void OnRebin( object self ) { self.ProcessImages("Rebin"); }
    void OnSharpen( object self ) { self.ProcessImages("Sharpen"); }
    void OnSmooth( object self ) { self.ProcessImages("Smooth"); }
    void OnLaplacian( object self ) { self.ProcessImages("Laplacian"); }
    void OnSobel( object self ) { self.ProcessImages("Sobel"); }
    void OnNonLinearFilter( object self ) { self.ProcessImages("Non-Linear Filter"); }
    void OnAutocorrelation( object self ) { self.ProcessImages("Autocorrelation"); }

    object CreateUI( object self )
	{
		TagGroup dialog_items;
		TagGroup dialog = DLGCreateDialog( "Batch Process Tools", dialog_items );
		number btn_w = 100;
		number btn_h = 25;

		TagGroup btn_flip_h    = DLGCreatePushButton( "Flip Horizontal", "OnFlipHorizontal" );  
		DLGWidth( btn_flip_h, btn_w ); DLGHeight( btn_flip_h, btn_h );
		
		TagGroup btn_flip_v    = DLGCreatePushButton( "Flip Vertical", "OnFlipVertical" );      
		DLGWidth( btn_flip_v, btn_w ); DLGHeight( btn_flip_v, btn_h );
		
		TagGroup btn_rot_r     = DLGCreatePushButton( "Rotate Right", "OnRotateRight" );        
		DLGWidth( btn_rot_r, btn_w ); DLGHeight( btn_rot_r, btn_h );
		
		TagGroup btn_rot_l     = DLGCreatePushButton( "Rotate Left", "OnRotateLeft" );          
		DLGWidth( btn_rot_l, btn_w ); DLGHeight( btn_rot_l, btn_h );
		
		TagGroup btn_fft       = DLGCreatePushButton( "FFT", "OnFFT" );                         
		DLGWidth( btn_fft, btn_w ); DLGHeight( btn_fft, btn_h );
		
		TagGroup btn_binned    = DLGCreatePushButton( "Binned FFT", "OnBinnedFFT" );            
		DLGWidth( btn_binned, btn_w ); DLGHeight( btn_binned, btn_h );
		
		TagGroup btn_rebin     = DLGCreatePushButton( "Rebin", "OnRebin" );         
		DLGWidth( btn_rebin, btn_w ); DLGHeight( btn_rebin, btn_h );
		
		TagGroup btn_sharpen   = DLGCreatePushButton( "Sharpen", "OnSharpen" );                     
		DLGWidth( btn_sharpen, btn_w ); DLGHeight( btn_sharpen, btn_h );
		
		TagGroup btn_smooth    = DLGCreatePushButton( "Smooth", "OnSmooth" );
		DLGWidth( btn_smooth, btn_w ); DLGHeight( btn_smooth, btn_h );
		
		TagGroup btn_laplacian = DLGCreatePushButton( "Laplacian", "OnLaplacian" );
		DLGWidth( btn_laplacian, btn_w ); DLGHeight( btn_laplacian, btn_h );
		
		TagGroup btn_sobel     = DLGCreatePushButton( "Sobel", "OnSobel" );
		DLGWidth( btn_sobel, btn_w ); DLGHeight( btn_sobel, btn_h );
		
		TagGroup btn_nonLinearFilter = DLGCreatePushButton( "Non-Linear Filter", "OnNonLinearFilter" );
		DLGWidth( btn_nonLinearFilter, btn_w ); DLGHeight( btn_nonLinearFilter, btn_h );
		
		TagGroup btn_autocorrelation = DLGCreatePushButton( "Autocorrelation", "OnAutocorrelation" );
		DLGWidth( btn_autocorrelation, btn_w ); DLGHeight( btn_autocorrelation, btn_h );                    
		
		
		TagGroup box_geo_items;
		TagGroup box_geo = DLGCreateBox( "Geometry and Scale", box_geo_items );
		box_geo_items.DLGAddElement( btn_flip_h );
		box_geo_items.DLGAddElement( btn_flip_v );
		box_geo_items.DLGAddElement( btn_rot_r );
		box_geo_items.DLGAddElement( btn_rot_l );
		box_geo_items.DLGAddElement( btn_rebin );
		dialog_items.DLGAddElement( box_geo );
		
		TagGroup box_filter_items;
		TagGroup box_filter = DLGCreateBox( "Filters", box_filter_items );
		box_filter_items.DLGAddElement( btn_sharpen );
		box_filter_items.DLGAddElement( btn_smooth );
		box_filter_items.DLGAddElement( btn_laplacian );
		box_filter_items.DLGAddElement( btn_sobel );
		box_filter_items.DLGAddElement( btn_nonLinearFilter );
		dialog_items.DLGAddElement( box_filter );
		
		TagGroup box_math_items;
		TagGroup box_math = DLGCreateBox( "Math and Frequency", box_math_items );
		box_math_items.DLGAddElement( btn_fft );
		box_math_items.DLGAddElement( btn_binned );
		box_math_items.DLGAddElement( btn_autocorrelation );
		dialog_items.DLGAddElement( box_math );
		
		TagGroup lbl_author = DLGCreateLabel( "Author: Meco" );
		TagGroup lbl_version = DLGCreateLabel( "Version: 1.0.0" );
		
		dialog_items.DLGAddElement( lbl_author ).DLGAnchor("West");
		dialog_items.DLGAddElement( lbl_version ).DLGAnchor("West");
		
		return self.super.init( dialog );
	}
}

object ui = alloc(BatchTransformerUI).CreateUI();
ui.Display("Batch Transformer");