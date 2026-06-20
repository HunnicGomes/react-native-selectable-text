#import "SelectableTextView.h"

#import <react/renderer/components/SelectableTextViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/SelectableTextViewSpec/EventEmitters.h>
#import <react/renderer/components/SelectableTextViewSpec/Props.h>
#import <react/renderer/components/SelectableTextViewSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

using namespace facebook::react;

@class SelectableTextView;

@interface SelectableUITextView : UITextView
@property (nonatomic, weak) SelectableTextView *parentSelectableTextView;
@end

@implementation SelectableUITextView

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    if (self.parentSelectableTextView) {
        return [self.parentSelectableTextView canPerformAction:action withSender:sender];
    }
    return [super canPerformAction:action withSender:sender];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    if (self.parentSelectableTextView) {
        NSMethodSignature *signature = [self.parentSelectableTextView methodSignatureForSelector:aSelector];
        if (signature) {
            return signature;
        }
    }
    return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    if (self.parentSelectableTextView) {
        [self.parentSelectableTextView forwardInvocation:anInvocation];
    } else {
        [super forwardInvocation:anInvocation];
    }
}

// Override copy to prevent default behavior on the text view itself
- (void)copy:(id)sender
{
    NSLog(@"iOS SelectableText - SelectableUITextView copy: called, but blocked");
    // Do nothing - this prevents the default copy action
}

@end

@interface SelectableTextView () <RCTSelectableTextViewViewProtocol>
@end

@implementation SelectableTextView {
    std::vector<std::string> _menuOptionsVector;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
    return concreteComponentDescriptorProvider<SelectableTextViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    NSLog(@"iOS SelectableText - initWithFrame called: %@", NSStringFromCGRect(frame));
    
    static const auto defaultProps = std::make_shared<const SelectableTextViewProps>();
    _props = defaultProps;

    _textView = [[SelectableUITextView alloc] init];
    ((SelectableUITextView *)_textView).parentSelectableTextView = self;
    _textView.delegate = self;
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.scrollEnabled = NO;
    _textView.backgroundColor = [UIColor clearColor];
    _textView.textContainerInset = UIEdgeInsetsZero;
    _textView.textContainer.lineFragmentPadding = 0;
    _textView.userInteractionEnabled = YES;
    
    // Force enable text selection gestures
    _textView.allowsEditingTextAttributes = NO;
    _textView.dataDetectorTypes = UIDataDetectorTypeNone;
    
    // Initialize with empty text - will be populated by child components
    _textView.text = @"";
    _menuOptions = @[];
    
    self.contentView = _textView;
    
    // Make sure the container can become first responder
    self.userInteractionEnabled = YES;
    
    NSLog(@"iOS SelectableText - initialization complete");
  }

  return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
    const auto &oldViewProps = *std::static_pointer_cast<SelectableTextViewProps const>(_props);
    const auto &newViewProps = *std::static_pointer_cast<SelectableTextViewProps const>(props);

    // Update menu options
    if (oldViewProps.menuOptions != newViewProps.menuOptions) {
        _menuOptionsVector = newViewProps.menuOptions;
        
        NSMutableArray<NSString *> *options = [[NSMutableArray alloc] init];
        for (const auto& option : _menuOptionsVector) {
            [options addObject:[NSString stringWithUTF8String:option.c_str()]];
        }
        _menuOptions = options;
    }

    [super updateProps:props oldProps:oldProps];
}

- (void)mountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
    [super mountChildComponentView:childComponentView index:index];
    // Don't add child to _textView, let React Native handle the text rendering through normal flow
    // The text content will be accessible through the component hierarchy
}

// Recursively unhide all child views. This is necessary because we previously set
// view.hidden = YES when extracting text. If we don't revert this, React Native's
// Fabric view recycling pool will reuse these hidden views elsewhere in the app,
// causing text to randomly disappear.
- (void)unhideAllViews:(UIView *)view
{
    view.hidden = NO;
    for (UIView *subview in view.subviews) {
        [self unhideAllViews:subview];
    }
}

- (void)unmountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
    // Ensure all views are visible again before returning them to the recycling pool
    [self unhideAllViews:childComponentView];
    [super unmountChildComponentView:childComponentView index:index];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    // Extract text from child components and set it on the UITextView
    [self updateTextViewContent];
}

- (void)updateTextViewContent
{
    NSMutableAttributedString *combinedAttributedText = [[NSMutableAttributedString alloc] init];
    
    // Recursively extract styled text from all child views and hide them
    [self extractStyledTextFromView:self intoAttributedString:combinedAttributedText hideViews:YES];
    
    NSLog(@"iOS SelectableText - Extracted styled text: '%@' (length: %lu)", combinedAttributedText.string, (unsigned long)combinedAttributedText.length);
    
    // Always update the text view with styled text
    _textView.attributedText = combinedAttributedText;
    
    // Log the final text view content
    NSLog(@"iOS SelectableText - TextView text: '%@'", _textView.text);
}

- (void)extractTextFromView:(UIView *)view intoString:(NSMutableString *)textString hideViews:(BOOL)hideViews
{
    NSLog(@"iOS SelectableText - Checking view: %@ (class: %@)", view, [view class]);
    
    BOOL foundText = NO;
    
    // Look for UILabel (which React Native Text components become)
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        NSLog(@"iOS SelectableText - Found UILabel with text: '%@'", label.text);
        if (label.text && label.text.length > 0) {
            [textString appendString:label.text];
            foundText = YES;
        }
    }
    // Check for React Native Fabric text components with attributedText
    else if ([view respondsToSelector:@selector(attributedText)]) {
        NSAttributedString *attributedText = [view performSelector:@selector(attributedText)];
        if (attributedText && attributedText.length > 0) {
            NSString *text = attributedText.string;
            NSLog(@"iOS SelectableText - Found attributed text: '%@'", text);
            [textString appendString:text];
            foundText = YES;
        }
    }
    // Also check for other text-containing views
    else if ([view respondsToSelector:@selector(text)]) {
        NSString *text = [view performSelector:@selector(text)];
        if (text && text.length > 0) {
            NSLog(@"iOS SelectableText - Found text view with text: '%@'", text);
            [textString appendString:text];
            foundText = YES;
        }
    }
    
    // Hide the view if it contains text and we're asked to hide views
    if (foundText && hideViews) {
        NSLog(@"iOS SelectableText - Hiding text view: %@", view);
        view.hidden = YES;
    }
    
    // Recursively check child views
    NSLog(@"iOS SelectableText - View has %lu subviews", (unsigned long)view.subviews.count);
    for (UIView *subview in view.subviews) {
        // Skip the textView itself to avoid infinite recursion
        if (subview != _textView) {
            [self extractTextFromView:subview intoString:textString hideViews:hideViews];
        }
    }
}

- (void)extractStyledTextFromView:(UIView *)view intoAttributedString:(NSMutableAttributedString *)attributedString hideViews:(BOOL)hideViews
{
    NSLog(@"iOS SelectableText - Checking styled view: %@ (class: %@)", view, [view class]);
    
    BOOL foundText = NO;
    
    // Check for React Native Fabric text components with attributedText (preserves styling)
    if ([view respondsToSelector:@selector(attributedText)]) {
        NSAttributedString *attributedText = [view performSelector:@selector(attributedText)];
        if (attributedText && attributedText.length > 0) {
            NSLog(@"iOS SelectableText - Found styled attributed text: '%@'", attributedText.string);
            [attributedString appendAttributedString:attributedText];
            foundText = YES;
        }
    }
    // Look for UILabel (which React Native Text components become) and preserve styling
    else if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.attributedText && label.attributedText.length > 0) {
            NSLog(@"iOS SelectableText - Found styled UILabel: '%@'", label.attributedText.string);
            [attributedString appendAttributedString:label.attributedText];
            foundText = YES;
        } else if (label.text && label.text.length > 0) {
            // Fallback to plain text if no attributed text
            NSAttributedString *plainText = [[NSAttributedString alloc] initWithString:label.text];
            [attributedString appendAttributedString:plainText];
            foundText = YES;
        }
    }
    // Also check for other text-containing views
    else if ([view respondsToSelector:@selector(text)]) {
        NSString *text = [view performSelector:@selector(text)];
        if (text && text.length > 0) {
            NSLog(@"iOS SelectableText - Found plain text view: '%@'", text);
            NSAttributedString *plainText = [[NSAttributedString alloc] initWithString:text];
            [attributedString appendAttributedString:plainText];
            foundText = YES;
        }
    }
    
    // Hide the view if it contains text and we're asked to hide views
    if (foundText && hideViews) {
        NSLog(@"iOS SelectableText - Hiding styled text view: %@", view);
        view.hidden = YES;
    }
    
    // Recursively check child views
    NSLog(@"iOS SelectableText - Styled view has %lu subviews", (unsigned long)view.subviews.count);
    for (UIView *subview in view.subviews) {
        // Skip the textView itself to avoid infinite recursion
        if (subview != _textView) {
            [self extractStyledTextFromView:subview intoAttributedString:attributedString hideViews:hideViews];
        }
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    NSLog(@"iOS SelectableText - touchesBegan called");
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    NSLog(@"iOS SelectableText - touchesEnded called");
    
    // Try to manually trigger text selection
    UITouch *touch = [touches anyObject];
    if (touch) {
        CGPoint location = [touch locationInView:_textView];
        NSLog(@"iOS SelectableText - Touch at: %@", NSStringFromCGPoint(location));
        
        // Trigger manual selection on long press
        static NSTimeInterval lastTouchTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        
        if (currentTime - lastTouchTime > 0.5) { // Long press simulation
            [self handleManualSelection:location];
        }
        lastTouchTime = currentTime;
    }
    
    [super touchesEnded:touches withEvent:event];
}

- (void)handleManualSelection:(CGPoint)location
{
    NSLog(@"iOS SelectableText - Handling manual selection at: %@", NSStringFromCGPoint(location));
    
    // Check if location is within text bounds
    if (!CGRectContainsPoint(_textView.bounds, location)) {
        NSLog(@"iOS SelectableText - Touch outside text bounds");
        return;
    }
    
    UITextPosition *textPosition = [_textView closestPositionToPoint:location];
    if (textPosition) {
        // Create a text range for the word at the touch point
        UITextRange *wordRange = [_textView.tokenizer rangeEnclosingPosition:textPosition 
                                                                 withGranularity:UITextGranularityWord 
                                                                     inDirection:UITextLayoutDirectionRight];
        if (wordRange) {
            _textView.selectedTextRange = wordRange;
            NSLog(@"iOS SelectableText - Selected word range");
            
            // Make sure text view becomes first responder
            [_textView becomeFirstResponder];
            
            // Show custom menu
            if (_menuOptions.count > 0) {
                [self showCustomMenu];
            } else {
                NSLog(@"iOS SelectableText - No menu options configured");
            }
        } else {
            NSLog(@"iOS SelectableText - Could not create word range");
        }
    } else {
        NSLog(@"iOS SelectableText - Could not find text position");
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        NSLog(@"iOS SelectableText - Long press detected on %@", gestureRecognizer.view);
        
        // Convert location to textView coordinates if needed
        CGPoint location;
        if (gestureRecognizer.view == _textView) {
            location = [gestureRecognizer locationInView:_textView];
        } else {
            location = [gestureRecognizer locationInView:self];
            location = [self convertPoint:location toView:_textView];
        }
        
        NSLog(@"iOS SelectableText - Touch location: %@", NSStringFromCGPoint(location));
        
        // Check if location is within text bounds
        CGRect textBounds = _textView.bounds;
        if (!CGRectContainsPoint(textBounds, location)) {
            NSLog(@"iOS SelectableText - Touch outside text bounds");
            return;
        }
        
        UITextPosition *textPosition = [_textView closestPositionToPoint:location];
        
        if (textPosition) {
            // Create a text range for the word at the touch point
            UITextRange *wordRange = [_textView.tokenizer rangeEnclosingPosition:textPosition 
                                                                     withGranularity:UITextGranularityWord 
                                                                         inDirection:UITextLayoutDirectionRight];
            if (wordRange) {
                _textView.selectedTextRange = wordRange;
                NSLog(@"iOS SelectableText - Selected word range");
                
                // Make sure text view becomes first responder
                [_textView becomeFirstResponder];
                
                // Show custom menu
                if (_menuOptions.count > 0) {
                    [self showCustomMenu];
                } else {
                    NSLog(@"iOS SelectableText - No menu options configured");
                }
            } else {
                NSLog(@"iOS SelectableText - Could not create word range");
            }
        } else {
            NSLog(@"iOS SelectableText - Could not find text position");
        }
    }
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    NSLog(@"iOS SelectableText - Selection changed: location=%lu, length=%lu", 
          (unsigned long)textView.selectedRange.location, 
          (unsigned long)textView.selectedRange.length);
    
    if (textView.selectedRange.length > 0 && _menuOptions.count > 0) {
        NSLog(@"iOS SelectableText - Showing custom menu with %lu options", (unsigned long)_menuOptions.count);
        // Delay showing menu to ensure selection is established
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showCustomMenu];
        });
    } else {
        // Hide menu if no selection
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:YES];
    }
}

- (void)showCustomMenu
{
    NSLog(@"iOS SelectableText - showCustomMenu called");
    
    // Ensure text view can become first responder
    if (![_textView canBecomeFirstResponder]) {
        NSLog(@"iOS SelectableText - textView cannot become first responder");
        return;
    }
    
    [_textView becomeFirstResponder];
    
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    
    // Clear existing menu items
    menuController.menuItems = nil;
    
    NSMutableArray<UIMenuItem *> *menuItems = [[NSMutableArray alloc] init];
    
    for (NSString *option in _menuOptions) {
        // Convert option to valid selector name (replace spaces and special chars with underscores)
        NSString *selectorName = [[option stringByReplacingOccurrencesOfString:@" " withString:@"_"] 
                                                stringByReplacingOccurrencesOfString:@"[^a-zA-Z0-9_]" 
                                                withString:@"_" 
                                                options:NSRegularExpressionSearch 
                                                range:NSMakeRange(0, option.length)];
        SEL action = NSSelectorFromString([NSString stringWithFormat:@"customAction_%@:", selectorName]);
        UIMenuItem *menuItem = [[UIMenuItem alloc] initWithTitle:option action:action];
        [menuItems addObject:menuItem];
        NSLog(@"iOS SelectableText - Added menu item: %@ with selector: customAction_%@:", option, selectorName);
    }
    
    menuController.menuItems = menuItems;
    
    NSLog(@"iOS SelectableText - Final menu items count: %lu", (unsigned long)menuItems.count);
    for (UIMenuItem *item in menuItems) {
        NSLog(@"iOS SelectableText - Menu item: '%@' action: %@", item.title, NSStringFromSelector(item.action));
    }
    
    // Force update the menu
    [menuController update];
    
    // Show menu at selection
    CGRect selectedRect = [_textView firstRectForRange:_textView.selectedTextRange];
    NSLog(@"iOS SelectableText - Selected rect: %@", NSStringFromCGRect(selectedRect));
    
    if (!CGRectIsEmpty(selectedRect)) {
        // Convert rect to view coordinates
        CGRect targetRect = [_textView convertRect:selectedRect toView:_textView];
        [menuController setTargetRect:targetRect inView:_textView];
        [menuController setMenuVisible:YES animated:YES];
        NSLog(@"iOS SelectableText - Menu should now be visible with %lu items", (unsigned long)menuItems.count);
    } else {
        NSLog(@"iOS SelectableText - Selected rect is empty, cannot show menu");
    }
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

// Support for custom menu actions
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    NSString *selectorName = NSStringFromSelector(action);
    NSLog(@"iOS SelectableText - canPerformAction called with: %@", selectorName);
    
    if ([selectorName hasPrefix:@"customAction_"] && [selectorName hasSuffix:@":"]) {
        NSLog(@"iOS SelectableText - canPerformAction: %@ -> YES", selectorName);
        return YES;
    }
    
    // Block ALL default system actions - we only want our custom ones
    NSLog(@"iOS SelectableText - Blocking default action: %@", selectorName);
    return NO;
}

// Override copy to prevent default behavior
- (void)copy:(id)sender
{
    NSLog(@"iOS SelectableText - copy: called, but blocked - should not happen");
    // Do nothing - this prevents the default copy action
}

// Dynamic method handling for custom menu actions
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    NSString *selectorName = NSStringFromSelector(aSelector);
    NSLog(@"iOS SelectableText - methodSignatureForSelector called with: %@", selectorName);
    if ([selectorName hasPrefix:@"customAction_"] && [selectorName hasSuffix:@":"]) {
        NSLog(@"iOS SelectableText - Providing signature for custom action: %@", selectorName);
        return [NSMethodSignature signatureWithObjCTypes:"v@:@"];
    }
    return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSString *selectorName = NSStringFromSelector(anInvocation.selector);
    NSLog(@"iOS SelectableText - forwardInvocation called with selector: %@", selectorName);
    
    if ([selectorName hasPrefix:@"customAction_"] && [selectorName hasSuffix:@":"]) {
        // Extract cleaned option name from selector and find the original option
        NSString *cleanedOption = [selectorName substringWithRange:NSMakeRange(13, selectorName.length - 14)];
        NSLog(@"iOS SelectableText - Extracted cleaned option: '%@' from selector: '%@'", cleanedOption, selectorName);
        
        // Find the original option that matches this cleaned selector
        NSString *originalOption = nil;
        for (NSString *option in _menuOptions) {
            NSString *testSelectorName = [[option stringByReplacingOccurrencesOfString:@" " withString:@"_"] 
                                                    stringByReplacingOccurrencesOfString:@"[^a-zA-Z0-9_]" 
                                                    withString:@"_" 
                                                    options:NSRegularExpressionSearch 
                                                    range:NSMakeRange(0, option.length)];
            if ([testSelectorName isEqualToString:cleanedOption]) {
                originalOption = option;
                break;
            }
        }
        
        if (originalOption) {
            NSLog(@"iOS SelectableText - Found original option: '%@' for cleaned option: '%@'", originalOption, cleanedOption);
            [self handleMenuSelection:originalOption];
        } else {
            NSLog(@"iOS SelectableText - Could not find original option for cleaned option: '%@'", cleanedOption);
        }
    } else {
        NSLog(@"iOS SelectableText - Selector doesn't match pattern, forwarding to super: %@", selectorName);
        [super forwardInvocation:anInvocation];
    }
}

- (void)handleMenuSelection:(NSString *)selectedOption
{
    NSRange selectedRange = _textView.selectedRange;
    NSString *selectedText = @"";
    
    if (selectedRange.location != NSNotFound && selectedRange.length > 0) {
        selectedText = [_textView.text substringWithRange:selectedRange];
    }
    
    NSLog(@"iOS SelectableText - handleMenuSelection called!");
    NSLog(@"iOS SelectableText - Selected: '%@' with option: '%@'", selectedText, selectedOption);
    NSLog(@"iOS SelectableText - Selected range: location=%lu, length=%lu", 
          (unsigned long)selectedRange.location, (unsigned long)selectedRange.length);
    
    // Clear selection
    _textView.selectedRange = NSMakeRange(0, 0);
    
    // Hide menu
    [[UIMenuController sharedMenuController] setMenuVisible:NO animated:YES];
    
    // Emit event using Fabric eventEmitter
    if (auto eventEmitter = std::static_pointer_cast<const SelectableTextViewEventEmitter>(_eventEmitter)) {
        NSLog(@"iOS SelectableText - Emitting selection event via Fabric eventEmitter");
        SelectableTextViewEventEmitter::OnSelection selectionEvent = {
            .chosenOption = std::string([selectedOption UTF8String]),
            .highlightedText = std::string([selectedText UTF8String])
        };
        eventEmitter->onSelection(selectionEvent);
    } else {
        NSLog(@"iOS SelectableText - No eventEmitter available");
    }
}

Class<RCTComponentViewProtocol> SelectableTextViewCls(void)
{
    return SelectableTextView.class;
}

@end