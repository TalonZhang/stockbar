#import "AddStockMenuItemView.h"

static const CGFloat AddRowWidth = 326.0;
static const CGFloat AddRowHeight = 34.0;

@interface AddStockMenuItemView ()

@property (nonatomic, strong) NSButton *entryButton;
@property (nonatomic) BOOL validating;

@end

@implementation AddStockMenuItemView

- (instancetype)initWithFrame:(NSRect)frameRect {
    (void)frameRect;
    self = [super initWithFrame:NSMakeRect(0, 0, AddRowWidth, AddRowHeight)];
    if (self) {
        self.entryButton = [NSButton buttonWithTitle:@"＋ 添加自选" target:self action:@selector(requestEditing:)];
        self.entryButton.bezelStyle = NSBezelStyleRounded;
        self.entryButton.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        self.entryButton.frame = NSMakeRect(16.0, 4.0, 294.0, 26.0);
        self.entryButton.toolTip = @"打开小窗，通过代码、中文名称或拼音缩写添加到当前分组";
        self.entryButton.accessibilityLabel = @"添加自选";
        [self addSubview:self.entryButton];
    }
    return self;
}

- (void)setValidating:(BOOL)validating {
    _validating = validating;
    self.entryButton.enabled = !validating;
    self.entryButton.title = validating ? @"正在验证…" : @"＋ 添加自选";
}

- (void)clearInput {
    [self setValidating:NO];
}

- (void)focusAndSelectInput {
    [self requestEditing:nil];
}

- (void)requestEditing:(id)sender {
    (void)sender;
    if (!self.validating && [self.delegate respondsToSelector:@selector(addStockMenuItemViewDidRequestEditing:)]) {
        [self.delegate addStockMenuItemViewDidRequestEditing:self];
    }
}

@end
