/* 
DigitalMicrograph Script: Live image statistics report
Periodically reads an image document by name and reports live statistics
(mean, min, max, std-dev, sum, size) on a modeless dialog.

MIT License, Copyright (c) 2026 Meco
Version: 1.0.0
Source: https://github.com/lmengchia
*/

number true = 1, false = 0

// Persistent-tag paths -------------------------------------------------------
string kTagTargetName = "LiveImageMonitor:TargetImageName"
string kTagInterval   = "LiveImageMonitor:IntervalSec"

// Default values -------------------------------------------------------------
string kDefaultTargetName = "View"
number kDefaultInterval   = 0.2   // seconds; 0.2 is a sane minimum for UI feel
number kMinInterval       = 0.05
number kMaxInterval       = 10.0


// -----------------------------------------------------------------------------
//  Interface the thread uses to call back into the dialog
// -----------------------------------------------------------------------------
Interface DialogInterface {
	void OnThreadFinished( object self );
	void UpdateStatistics( object self, string meanVal, string minVal, string maxVal, string stdVal, string sumVal,string sizeVal, string statusVal );
}


// -----------------------------------------------------------------------------
//  Counting_Thread - background worker
// -----------------------------------------------------------------------------
Class Counting_Thread : Thread {
	Object cancelSignal
	Number dialogID
	Number intervalSec

	Counting_Thread( object self ) {
	//	Result( "\nCounting_Thread created (ID: " + self.ScriptObjectGetID() + ")" )
	}

	~Counting_Thread( object self ) {
	//	Result( "\nCounting_Thread destroyed (ID: " + self.ScriptObjectGetID() + ")" )
	}

	// Called from the UI thread BEFORE StartThread so that dialogID and
	// interval are in place when RunThread begins.
	object init( object self, number dlgID, number interval ) {
		cancelSignal = NewSignal( 0 )
		dialogID = dlgID
		intervalSec = interval
		return self
	}

	void UpdateInterval( object self, number interval ) {
		intervalSec = interval
	}

	void Stop( object self ) {
		if ( cancelSignal.ScriptObjectIsValid() )
			cancelSignal.SetSignal()
	}

	// Find an image document by name. Returns an invalid ImageDocument if not
	// found. Pass an empty string to match the front-most document.
	ImageDocument FindDocByName( object self, string targetName ) {
		ImageDocument doc
		if ( targetName == "" )
			return GetFrontImageDocument()

		number n = CountImageDocuments()
		for ( number i = 0; i < n; i++ ) {
			doc = GetImageDocument( i )
			if ( doc.ImageDocumentIsValid() && doc.ImageDocumentGetName() == targetName )
				return doc
		}
		return ImageDocumentNullify( NULL )
	}

	// Gather statistics on the first image of the document in a single pass.
	// Sets `statsAvailable` to 1 when the image has a statistics-compatible
	// data type (Real / Integer / Binary). For other data types (Complex,
	// Packed Complex, RGB) the size string is still filled in but numeric
	// readouts are blanked out and `statsAvailable` is set to 0.
	void GatherStatistics( object self, ImageDocument doc, string &meanStr, string &minStr, string &maxStr, string &stdStr, string &sumStr, string &sizeStr, number &statsAvailable ) {
		image img := doc.ImageDocumentGetImage( 0 )
		if ( !img.ImageIsValid() ) {
			meanStr = "-" ; minStr = "-" ; maxStr = "-"
			stdStr  = "-" ; sumStr = "-" ; sizeStr = "-"
			statsAvailable = 0
			return
		}

		// Size string: always available regardless of data type.
		number nd = img.ImageGetNumDimensions()
		string s = "" + img.ImageGetDimensionSize( 0 )
		for ( number d = 1; d < nd; d++ )
			s += " x " + img.ImageGetDimensionSize( d )
		sizeStr = s

		// Statistics are only meaningful for scalar (Real / Integer / Binary)
		// data. Complex, Packed Complex and RGB images are skipped.
		number isSupported = img.ImageIsDataTypeReal()    \
		                  || img.ImageIsDataTypeInteger() \
		                  || img.ImageIsDataTypeBinary()

		if ( !isSupported ) {
			meanStr = "-" ; minStr = "-" ; maxStr = "-"
			stdStr  = "-" ; sumStr = "-"
			statsAvailable = 0
			return
		}

		number mn, va
		img.ImageGetMeanAndVariance( mn, va )
		number mnVal = img.ImageGetMinimum()
		number mxVal = img.ImageGetMaximum()
		number sumVal = img.ImageGetSum()
		number sd = sqrt( va )

		meanStr = format( mn, "%.3f" )
		minStr  = format( mnVal, "%.3f" )
		maxStr  = format( mxVal, "%.3f" )
		stdStr  = format( sd, "%.3f" )
		sumStr  = format( sumVal, "%.3e" )
		statsAvailable = 1
	}

	// Main thread loop - overrides Thread::RunThread().
	void RunThread( object self ) {
		// Result( "\nThread started." )

		object calledDialog = GetScriptObjectFromID( dialogID )
		if ( !calledDialog.ScriptObjectIsValid() ) {
			Result( "\nInvalid dialog id; thread aborting." )
			return
		}

		DocumentWindow dialogWin = calledDialog.GetFrameWindow()

		// Dummy signal that is never set; waiting on it with cancelSignal as
		// the cancel parameter gives us an interruptible sleep: it returns
		// normally when the timeout elapses and throws when Stop() is called.
		object dummySignal = NewSignal( 0 )

		string meanStr, minStr, maxStr, stdStr, sumStr, sizeStr, statusStr
		string targetName
		number stopRequested = 0

		while ( !stopRequested ) {
			// Abort immediately if the dialog window is gone.
			if ( !WindowIsOpen( dialogWin ) ) break

			try {
				calledDialog.DLGGetValue( "targetImageName", targetName )
				ImageDocument doc = self.FindDocByName( targetName )

				if ( doc.ImageDocumentIsValid() ) {
					number statsAvailable = 0
					self.GatherStatistics( doc, meanStr, minStr, maxStr, stdStr, sumStr, sizeStr, statsAvailable )
					if ( statsAvailable )
						statusStr = "OK   " + GetTime( 1 )
					else
						statusStr = "Not applicable   " + GetTime( 1 )
				} else {
					meanStr = "-" ; minStr = "-" ; maxStr = "-"
					stdStr  = "-" ; sumStr = "-" ; sizeStr = "-"
					statusStr = "Not found   " + GetTime( 1 )
				}

				calledDialog.UpdateStatistics( meanStr, minStr, maxStr, stdStr, sumStr, sizeStr, statusStr )
			} catch {
				Result( "\nLoop error - continuing." )
				break
			}

			// Interruptible sleep: returns after intervalSec, or throws
			// immediately when Stop() sets cancelSignal.
			try {
				dummySignal.WaitOnSignal( intervalSec, cancelSignal )
			} catch {
				stopRequested = 1
				break
			}
		}

		if ( WindowIsOpen( dialogWin ) )
			calledDialog.OnThreadFinished()

		// Result( "\nThread finished." )
	}
}


// -----------------------------------------------------------------------------
//  Dialog_UI - the user interface
// -----------------------------------------------------------------------------
Class Dialog_UI : UIFrame
{
	object workerThread
	object threadTemplate   // Template object used to clone new threads from
	                        // (required because Alloc() inside a method call
	                        // cannot resolve the class name unless installed
	                        // as a library — see "Template objects" in the
	                        // DM scripting documentation.)

	// ---- helpers ----
	void SetLabel( object self, string identifier, string text ) {
		TagGroup tg = self.LookupElement( identifier )
		if ( tg.TagGroupIsValid() )
			tg.DLGTitle( text )
	}

	number GetIntervalFromUI( object self ) {
		number v = 0
		self.DLGGetValue( "interval", v )
		if ( v < kMinInterval ) v = kMinInterval
		if ( v > kMaxInterval ) v = kMaxInterval
		return v
	}

	// ---- button handlers ----
	void OnStart( object self ) {
		// If an old thread is still alive, ignore the click.
		
		if ( workerThread.ScriptObjectIsValid() ) {
			Result( "\nMonitor already running." )
			return
		}
		
		number interval = self.GetIntervalFromUI()
		self.SetElementIsEnabled( "startbutton", 0 )
		self.SetElementIsEnabled( "stopbutton",  1 )
		self.SetElementIsEnabled( "interval",    0 )
		self.SetElementIsEnabled( "targetImageName", 0 )

		// Clone the template instead of Alloc()ing a new one. Alloc with a
		// class name only works from top-level script code or library code,
		// not from inside a method call, so we keep a template around.
		workerThread = threadTemplate.ScriptObjectClone()
		workerThread.init( self.ScriptObjectGetID(), interval )
		workerThread.StartThread( "RunThread" )
	}

	void OnStop( object self ) {
		if ( workerThread.ScriptObjectIsValid() )
			workerThread.Stop()
	}

	// Called by the thread when it has finished.
	void OnThreadFinished( object self ) {
		self.SetElementIsEnabled( "startbutton", 1 )
		self.SetElementIsEnabled( "stopbutton",  0 )
		self.SetElementIsEnabled( "interval",    1 )
		self.SetElementIsEnabled( "targetImageName", 1 )
		self.SetLabel( "statusVal", "Stopped" )
		workerThread = NULL
	}

	// Called by the worker thread on every tick.
	void UpdateStatistics( object self, string meanVal, string minVal, string maxVal, string stdVal, string sumVal,string sizeVal, string statusVal ) {
		self.SetLabel( "meanVal",   meanVal )
		self.SetLabel( "minVal",    minVal )
		self.SetLabel( "maxVal",    maxVal )
		self.SetLabel( "stdVal",    stdVal )
		self.SetLabel( "sumVal",    sumVal )
		self.SetLabel( "sizeVal",   sizeVal )
		self.SetLabel( "statusVal", statusVal )
	}

	// ---- UI events ----
	void TargetNameChanged( object self, taggroup tg ) {
		string name = tg.DLGGetStringValue()
		if ( name == "" ) { name = kDefaultTargetName; tg.DLGValue( name ); }
		SetPersistentStringNote( kTagTargetName, name )
	}

	void IntervalChanged( object self, taggroup tg ) {
		number v = tg.DLGGetValue()
		if ( v < kMinInterval ) { v = kMinInterval; tg.DLGValue( v ); }
		if ( v > kMaxInterval ) { v = kMaxInterval; tg.DLGValue( v ); }
		SetPersistentNumberNote( kTagInterval, v )
		if ( workerThread.ScriptObjectIsValid() )
			workerThread.UpdateInterval( v )
	}

	// ---- dialog construction ----
	TagGroup BuildReadoutRow( object self, string label, string identifier ) {
		TagGroup lbl = DLGCreateLabel( label, 14 )
		TagGroup val = DLGCreateLabel( "-", 20 ).DLGIdentifier( identifier ).DLGAnchor( "West" )
		return DLGGroupItems( lbl, val ).DLGTableLayout( 2, 1, 0 )
	}

	TagGroup CreateDialog_UI( object self ) {
		TagGroup dialog_items
		TagGroup dialog = DLGCreateDialog( "Live Image Statistics Report", dialog_items ).DLGTableLayout( 1, 3, 0 )

		// --- target image + interval in a single 2-column, 2-row grid so
		//     that the two labels and the two fields line up with each other
		//     and all sit flush against the left edge.
		string targetName
		if ( !GetPersistentStringNote( kTagTargetName, targetName ) || targetName == "" )
			targetName = kDefaultTargetName

		number interval
		if ( !GetPersistentNumberNote( kTagInterval, interval ) )
			interval = kDefaultInterval
		if ( interval < kMinInterval ) interval = kMinInterval
		if ( interval > kMaxInterval ) interval = kMaxInterval

		TagGroup lbl_image = DLGCreateLabel( "Target image: ", 18 ).DLGAnchor( "West" )
		TagGroup val_image = DLGCreateStringField( targetName, 20 ).DLGChangedMethod( "TargetNameChanged" ).DLGIdentifier( "targetImageName" ).DLGAnchor( "West" )

		TagGroup lbl_int = DLGCreateLabel( "Update interval (s) ", 18 ).DLGAnchor( "West" )
		TagGroup val_int = DLGCreateRealField( interval, 8, 3 ).DLGChangedMethod( "IntervalChanged" ).DLGIdentifier( "interval" ).DLGAnchor( "West" )

		TagGroup settings_items
		TagGroup settings_grp = DLGCreateGroup( settings_items )
		settings_grp.DLGTableLayout( 2, 2, 0 ).DLGAnchor( "West" ).DLGSide( "Left" )
		settings_items.DLGAddElement( lbl_image )
		settings_items.DLGAddElement( val_image )
		settings_items.DLGAddElement( lbl_int )
		settings_items.DLGAddElement( val_int )

		// --- statistics read-outs ---
		TagGroup row_size   = self.BuildReadoutRow( "Size:   ", "sizeVal" )
		TagGroup row_mean   = self.BuildReadoutRow( "Mean:   ", "meanVal" )
		TagGroup row_min    = self.BuildReadoutRow( "Min:    ", "minVal" )
		TagGroup row_max    = self.BuildReadoutRow( "Max:    ", "maxVal" )
		TagGroup row_std    = self.BuildReadoutRow( "StdDev: ", "stdVal" )
		TagGroup row_sum    = self.BuildReadoutRow( "Sum:    ", "sumVal" )
		TagGroup row_status = self.BuildReadoutRow( "Status: ", "statusVal" )

		TagGroup box_items
		TagGroup stats_box = DLGCreateBox( "Statistics", box_items )
		box_items.DLGAddElement( row_size )
		box_items.DLGAddElement( row_mean )
		box_items.DLGAddElement( row_min )
		box_items.DLGAddElement( row_max )
		box_items.DLGAddElement( row_std )
		box_items.DLGAddElement( row_sum )
		box_items.DLGAddElement( row_status )

		// --- buttons ---
		TagGroup btn_start = DLGCreatePushButton( "Start", "OnStart" ).DLGIdentifier( "startbutton" )
		TagGroup btn_stop  = DLGCreatePushButton( "Stop",  "OnStop"  ).DLGIdentifier( "stopbutton" )
		TagGroup group_btns = DLGGroupItems( btn_start, btn_stop ).DLGTableLayout( 2, 1, 0 )

		// --- assemble ---
		dialog_items.DLGAddElement( settings_grp )
		dialog_items.DLGAddElement( stats_box )
		dialog_items.DLGAddElement( group_btns )

		return dialog
	}

	// ---- life-cycle ----
	Dialog_UI( object self ) {
	//	Result( "\nDialog created (ID: " + self.ScriptObjectGetID() + ")" )
	}

	~Dialog_UI( object self ) {
		// Make sure the thread is told to stop when the dialog is destroyed.
		if ( workerThread.ScriptObjectIsValid() )
			workerThread.Stop()
	//	Result( "\nDialog destroyed (ID: " + self.ScriptObjectGetID() + ")" )
	}

	Object LaunchDialog( object self ) {
		// Pre-allocate a template thread object. New worker threads will be
		// cloned from this template when Start is pressed, sidestepping the
		// "Cannot find class named ..." error that occurs when Alloc() is
		// called by class name from inside a method callback.
		threadTemplate = Alloc( Counting_Thread )
		
		self.init( self.CreateDialog_UI() )
		self.Display( "Live Image Statistics Report" )
		// Stop button disabled until Start is pressed
		self.SetElementIsEnabled( "stopbutton", 0 )
		self.SetLabel( "statusVal", "Idle" )
		return self
	}
}


void main() {
	Alloc( Dialog_UI ).LaunchDialog()
}
main()