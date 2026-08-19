#import "AddStockMenuItemView.h"

static const CGFloat AddRowWidth = 326.0;
static const CGFloat AddRowHeight = 34.0;

@interface AddStockMenuItemView ()

@property (nonatomic, strong) NSTextField *inputField;
@property (nonatomic) BOOL validating;

@end

@implementation AddStockMenuItemView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:NSMakeRect(0, 0, AddRowWidth, AddRowHeight)];
    if (self) {
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(16.0, 7.0, 86.0, 21.0)];
        label.bezeled = NO;
        label.drawsBackground = NO;
        label.editable = NO;
        label.selectable = NO;
        label.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        label.stringValue = @"添加自选股";
        [self addSubview:label];

        self.inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(108.0, 5.0, 202.0, 24.0)];
        self.inputField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.inputField.placeholderString = @"仅支持 A 股 6 位代码";
        self.inputField.toolTip = @"输入六位股票代码后按回车添加";
        self.inputField.target = self;
        self.inputField.action = @selector(submitInput:);
        [self addSubview:self.inputField];
    }
    return self;
}

- (void)submitInput:(id)sender {
    (void)sender;
    if (self.validating) {
        return;
    }
    NSString *input = [self.inputField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (input.length == 0) {
        NSBeep();
        [self focusAndSelectInput];
        return;
    }
    [self.delegate addStockMenuItemView:self didSubmitInput:input];
}

- (void)setValidating:(BOOL)validating {
    _validating = validating;
    self.inputField.enabled = !validating;
    self.inputField.placeholderString = validating ? @"正在验证…" : @"仅支持 A 股 6 位代码";
}

- (void)clearInput {
    self.inputField.stringValue = @"";
    [self setValidating:NO];
}

- (void)focusAndSelectInput {
    [self.window makeFirstResponder:self.inputField];
    [self.inputField selectText:nil];
}

@end
