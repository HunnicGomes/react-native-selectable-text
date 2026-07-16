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
    // Do nothing - this prevents the default copy action
}

@end

@interface SelectableTextView () <RCTSelectableTextViewViewProtocol>
@end

@implementation SelectableTextView {
    std::vector<std::string> _menuOptionsVector;
    NSDictionary<NSString *, NSString *> *_menuOptionSelectors;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
    return concreteComponentDescriptorProvider<SelectableTextViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    
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
        NSMutableDictionary<NSString *, NSString *> *selectors = [[NSMutableDictionary alloc] init];

        static NSRegularExpression *regex = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            regex = [NSRegularExpression regularExpressionWithPattern:@"[^a-zA-Z0-9_]"
                                                              options:0
                                                                error:nil];
        });

        for (const auto& opt : _menuOptionsVector) {
            NSString *option = [NSString stringWithUTF8String:opt.c_str()];
            [options addObject:option];

            // Pre-compute the valid selector name (replace spaces and special chars with underscores)
            NSString *intermediate = [option stringByReplacingOccurrencesOfString:@" " withString:@"_"];
            NSString *selectorName = [regex stringByReplacingMatchesInString:intermediate
                                                                     options:0
                                                                       range:NSMakeRange(0, intermediate.length)
                                                                withTemplate:@"_"];
            selectors[option] = selectorName;
        }
        _menuOptions = options;
        _menuOptionSelectors = selectors;
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
    
    
    // Always update the text view with styled text
    _textView.attributedText = combinedAttributedText;
    
    // Log the final text view content
}

- (void)extractTextFromView:(UIView *)view intoString:(NSMutableString *)textString hideViews:(BOOL)hideViews
{
    
    BOOL foundText = NO;
    
    // Look for UILabel (which React Native Text components become)
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
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
            [textString appendString:text];
            foundText = YES;
        }
    }
    // Also check for other text-containing views
    else if ([view respondsToSelector:@selector(text)]) {
        NSString *text = [view performSelector:@selector(text)];
        if (text && text.length > 0) {
            [textString appendString:text];
            foundText = YES;
        }
    }
    
    // Hide the view if it contains text and we're asked to hide views
    if (foundText && hideViews) {
        view.hidden = YES;
    }
    
    // Recursively check child views
    for (UIView *subview in view.subviews) {
        // Skip the textView itself to avoid infinite recursion
        if (subview != _textView) {
            [self extractTextFromView:subview intoString:textString hideViews:hideViews];
        }
    }
}

- (void)extractStyledTextFromView:(UIView *)view intoAttributedString:(NSMutableAttributedString *)attributedString hideViews:(BOOL)hideViews
{
    
    BOOL foundText = NO;
    
    // Check for React Native Fabric text components with attributedText (preserves styling)
    if ([view respondsToSelector:@selector(attributedText)]) {
        NSAttributedString *attributedText = [view performSelector:@selector(attributedText)];
        if (attributedText && attributedText.length > 0) {
            [attributedString appendAttributedString:attributedText];
            foundText = YES;
        }
    }
    // Look for UILabel (which React Native Text components become) and preserve styling
    else if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.attributedText && label.attributedText.length > 0) {
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
            NSAttributedString *plainText = [[NSAttributedString alloc] initWithString:text];
            [attributedString appendAttributedString:plainText];
            foundText = YES;
        }
    }
    
    // Hide the view if it contains text and we're asked to hide views
    if (foundText && hideViews) {
        view.hidden = YES;
    }
    
    // Recursively check child views
    for (UIView *subview in view.subviews) {
        // Skip the textView itself to avoid infinite recursion
        if (subview != _textView) {
            [self extractStyledTextFromView:subview intoAttributedString:attributedString hideViews:hideViews];
        }
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    
    // Try to manually trigger text selection
    UITouch *touch = [touches anyObject];
    if (touch) {
        CGPoint location = [touch locationInView:_textView];
        
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
    
    // Check if location is within text bounds
    if (!CGRectContainsPoint(_textView.bounds, location)) {
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
            
            // Make sure text view becomes first responder
            [_textView becomeFirstResponder];
            
            // Show custom menu
            if (_menuOptions.count > 0) {
                [self showCustomMenu];
            }
        }
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        
        // Convert location to textView coordinates if needed
        CGPoint location;
        if (gestureRecognizer.view == _textView) {
            location = [gestureRecognizer locationInView:_textView];
        } else {
            location = [gestureRecognizer locationInView:self];
            location = [self convertPoint:location toView:_textView];
        }
        
        
        // Check if location is within text bounds
        CGRect textBounds = _textView.bounds;
        if (!CGRectContainsPoint(textBounds, location)) {
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
                
                // Make sure text view becomes first responder
                [_textView becomeFirstResponder];
                
                // Show custom menu
                if (_menuOptions.count > 0) {
                    [self showCustomMenu];
                }
            }
        }
    }
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    
    if (textView.selectedRange.length > 0 && _menuOptions.count > 0) {
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
    
    // Ensure text view can become first responder
    if (![_textView canBecomeFirstResponder]) {
        return;
    }
    
    [_textView becomeFirstResponder];
    
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    
    // Clear existing menu items
    menuController.menuItems = nil;
    
    NSMutableArray<UIMenuItem *> *menuItems = [[NSMutableArray alloc] init];
    
    for (NSString *option in _menuOptions) {
        // Convert option to valid selector name (replace spaces and special chars with underscores)
        NSString *selectorName = _menuOptionSelectors[option];
        if (!selectorName) continue; // Fallback in case of mismatch

        SEL action = NSSelectorFromString([NSString stringWithFormat:@"customAction_%@:", selectorName]);
        UIMenuItem *menuItem = [[UIMenuItem alloc] initWithTitle:option action:action];
        [menuItems addObject:menuItem];
    }
    
    menuController.menuItems = menuItems;
    

    
    // Force update the menu
    [menuController update];
    
    // Show menu at selection
    CGRect selectedRect = [_textView firstRectForRange:_textView.selectedTextRange];
    
    if (!CGRectIsEmpty(selectedRect)) {
        // Convert rect to view coordinates
        CGRect targetRect = [_textView convertRect:selectedRect toView:_textView];
        [menuController setTargetRect:targetRect inView:_textView];
        [menuController setMenuVisible:YES animated:YES];
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
    
    if ([selectorName hasPrefix:@"customAction_"] && [selectorName hasSuffix:@":"]) {
        return YES;
    }
    
    // Block ALL default system actions - we only want our custom ones
    return NO;
}

// Override copy to prevent default behavior
- (void)copy:(id)sender
{
    // Do nothing - this prevents the default copy action
}

// Dynamic method handling for custom menu actions
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    NSString *selectorName = NSStringFromSelector(aSelector);
    if ([selectorName hasPrefix:@"customAction_"] && [selectorName hasSuffix:@":"]) {
        return [NSMethodSignature signatureWithObjCTypes:"v@:@"];
    }
    return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSString *selectorName = NSStringFromSelector(anInvocation.selector);
    
    if ([selectorName hasPrefix:@"customAction_"] && [selectorName hasSuffix:@":"]) {
        // Extract cleaned option name from selector and find the original option
        NSString *cleanedOption = [selectorName substringWithRange:NSMakeRange(13, selectorName.length - 14)];
        
        // Find the original option that matches this cleaned selector
        NSString *originalOption = nil;
        for (NSString *option in _menuOptions) {
            NSString *testSelectorName = _menuOptionSelectors[option];
            if ([testSelectorName isEqualToString:cleanedOption]) {
                originalOption = option;
                break;
            }
        }
        
        if (originalOption) {
            [self handleMenuSelection:originalOption];
        }
    } else {
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
    
    
    // Clear selection
    _textView.selectedRange = NSMakeRange(0, 0);
    
    // Hide menu
    [[UIMenuController sharedMenuController] setMenuVisible:NO animated:YES];
    
    // Emit event using Fabric eventEmitter
    if (auto eventEmitter = std::static_pointer_cast<const SelectableTextViewEventEmitter>(_eventEmitter)) {
        SelectableTextViewEventEmitter::OnSelection selectionEvent = {
            .chosenOption = std::string([selectedOption UTF8String]),
            .highlightedText = std::string([selectedText UTF8String])
        };
        eventEmitter->onSelection(selectionEvent);
    }
}

Class<RCTComponentViewProtocol> SelectableTextViewCls(void)
{
    return SelectableTextView.class;
}

@end
