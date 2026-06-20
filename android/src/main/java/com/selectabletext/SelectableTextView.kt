package com.selectabletext

import android.content.Context
import android.util.AttributeSet
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

class SelectableTextView : FrameLayout {
  private var menuOptions: Array<String> = emptyArray()
  private var textView: TextView? = null
  
  constructor(context: Context?) : super(context!!)
  constructor(context: Context?, attrs: AttributeSet?) : super(context!!, attrs)
  constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int) : super(
    context!!,
    attrs,
    defStyleAttr
  )
  
  fun setMenuOptions(options: Array<String>) {
    this.menuOptions = options
    setupTextView()
  }
  
  // Hook the child view as soon as it is added by React Native.
  // This eliminates timing issues where children are not yet attached during setup.
  override fun addView(child: View?, index: Int, params: ViewGroup.LayoutParams?) {
    super.addView(child, index, params)
    if (child is TextView) {
      textView = child
      setupSelectionCallback(child)
    }
  }
  
  private fun setupTextView() {
    // Find the first TextView child
    for (i in 0 until childCount) {
      val child = getChildAt(i)
      if (child is TextView) {
        textView = child
        setupSelectionCallback(child)
        break
      }
    }
  }
  
  private fun setupSelectionCallback(textView: TextView) {
    // Only call setTextIsSelectable if it is not already selectable.
    // This avoids triggering unnecessary native layout requests.
    if (!textView.isTextSelectable) {
      textView.setTextIsSelectable(true)
    }
    textView.customSelectionActionModeCallback = object : ActionMode.Callback {
      override fun onCreateActionMode(mode: ActionMode?, menu: Menu?): Boolean {
        return true
      }
      
      override fun onPrepareActionMode(mode: ActionMode?, menu: Menu?): Boolean {
        menu?.clear()
        menuOptions.forEachIndexed { index, option ->
          menu?.add(0, index, 0, option)
        }
        return true
      }
      
      override fun onActionItemClicked(mode: ActionMode?, item: MenuItem?): Boolean {
        val selectionStart = textView.selectionStart
        val selectionEnd = textView.selectionEnd
        val selectedText = textView.text.toString().substring(selectionStart, selectionEnd)
        val chosenOption = menuOptions[item?.itemId ?: 0]
        
        // Send event to React Native
        onSelectionEvent(chosenOption, selectedText)
        
        mode?.finish()
        return true
      }
      
      override fun onDestroyActionMode(mode: ActionMode?) {
        // Called when action mode is destroyed
      }
    }
  }
  
  private fun onSelectionEvent(chosenOption: String, highlightedText: String) {
    val reactContext = context as ReactContext
    val params = Arguments.createMap().apply {
      putInt("viewTag", id)
      putString("chosenOption", chosenOption)
      putString("highlightedText", highlightedText)
    }
    
    reactContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit("SelectableTextSelection", params)
  }

  // Override onMeasure to directly set dimensions from React Native (Yoga).
  // We do not call super.onMeasure() because FrameLayout's native measurement pass
  // would measure the child TextView using Android's standard specifications (often 0 or unspecified),
  // causing it to cache a tiny width and render text vertically (single-character wrapping).
  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    val widthSize = MeasureSpec.getSize(widthMeasureSpec)
    val heightSize = MeasureSpec.getSize(heightMeasureSpec)
    setMeasuredDimension(widthSize, heightSize)
  }
  
  // Override onLayout as a no-op (except for setting up the child ref if needed).
  // We do not call super.onLayout() because child views are positioned directly by Yoga
  // via child.layout() calls, and FrameLayout's layout pass would override this.
  override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
    if (changed && textView == null) {
      setupTextView()
    }
  }

  // Override requestLayout to prevent native layout requests from bubbling up.
  // Changes to selection state on standard TextViews trigger native layout passes,
  // which will collapse/override Yoga's layout calculations if not suppressed.
  override fun requestLayout() {
    // No-op: Prevent native layout requests from interfering with Yoga's layout tree.
  }
}
