#import "StockMenuItemView.h"

#import <math.h>

#import "StockQuote.h"

static const CGFloat StockRowWidth = 326.0;
static const CGFloat StockRowHeight = 28.0;

@interface StockMenuItemView ()

@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *percentLabel;
@property (nonatomic, strong) NSTextField *priceLabel;
@property (nonatomic, strong) NSButton *deleteButton;
@property (nonatomic, copy) NSString *stockCode;
@property (nonatomic, strong, nullable) NSTrackingArea *hoverTrackingArea;
@property (nonatomic, getter=isHovered) BOOL hovered;

@end

@implementation StockMenuItemView

- (instancetype)initWithQuote:(StockQuote *)quote {
    self = [super initWithFrame:NSMakeRect(0, 0, StockRowWidth, StockRowHeight)];
    if (self) {
        [self configureLabels];
        [self updateWithQuote:quote];
    }
    return self;
}

- (void)configureLabels {
    self.nameLabel = [self labelWithFrame:NSMakeRect(16.0, 3.0, 112.0, 22.0)
                               alignment:NSTextAlignmentLeft];
    self.percentLabel = [self labelWithFrame:NSMakeRect(132.0, 3.0, 72.0, 22.0)
                                  alignment:NSTextAlignmentRight];
    self.priceLabel = [self labelWithFrame:NSMakeRect(207.0, 3.0, 74.0, 22.0)
                                alignment:NSTextAlignmentRight];

    self.nameLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    if (@available(macOS 10.15, *)) {
        self.percentLabel.font = [NSFont monospacedDigitSystemFontOfSize:13.0 weight:NSFontWeightRegular];
        self.priceLabel.font = [NSFont monospacedDigitSystemFontOfSize:13.0 weight:NSFontWeightRegular];
    } else {
        self.percentLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        self.priceLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    }

    [self addSubview:self.nameLabel];
    [self addSubview:self.percentLabel];
    [self addSubview:self.priceLabel];

    self.deleteButton = [[NSButton alloc] initWithFrame:NSMakeRect(292.0, 4.0, 20.0, 20.0)];
    self.deleteButton.bordered = NO;
    self.deleteButton.imagePosition = NSImageOnly;
    self.deleteButton.toolTip = @"删除自选股";
    self.deleteButton.target = self;
    self.deleteButton.action = @selector(requestDelete:);
    self.deleteButton.hidden = YES;
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
                                   accessibilityDescription:@"删除"];
        image.template = YES;
        self.deleteButton.image = image;
    } else {
        self.deleteButton.title = @"×";
        self.deleteButton.imagePosition = NSNoImage;
    }
    [self addSubview:self.deleteButton];
}

- (NSTextField *)labelWithFrame:(NSRect)frame alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.alignment = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (void)updateWithQuote:(StockQuote *)quote {
    self.stockCode = quote.code;
    self.nameLabel.stringValue = quote.name.length > 0 ? quote.name : quote.code;
    self.toolTip = [NSString stringWithFormat:@"%@ · %@", quote.name, quote.code];

    if (!quote.isAvailable) {
        self.percentLabel.stringValue = @"--";
        self.priceLabel.stringValue = @"--";
        self.percentLabel.textColor = NSColor.secondaryLabelColor;
        self.priceLabel.textColor = NSColor.secondaryLabelColor;
        self.accessibilityLabel = [NSString stringWithFormat:@"%@，行情暂不可用", self.nameLabel.stringValue];
        return;
    }

    self.percentLabel.stringValue = [NSString stringWithFormat:@"%+.2f%%", quote.percentChange];
    self.priceLabel.stringValue = [@"¥" stringByAppendingString:quote.formattedPrice];

    NSColor *movementColor;
    if (fabs(quote.percentChange) < 0.0001) {
        movementColor = NSColor.secondaryLabelColor;
    } else {
        movementColor = quote.percentChange > 0.0 ? NSColor.systemRedColor : NSColor.systemGreenColor;
    }
    self.percentLabel.textColor = movementColor;
    self.priceLabel.textColor = movementColor;
    NSString *direction = quote.percentChange > 0.0 ? @"上涨" : (quote.percentChange < 0.0 ? @"下跌" : @"平盘");
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@ %.2f%%，现价 %@元",
                               self.nameLabel.stringValue,
                               direction,
                               fabs(quote.percentChange),
                               quote.formattedPrice];
}

- (void)setDraggable:(BOOL)draggable {
    _draggable = draggable;
    [self.window invalidateCursorRectsForView:self];
}

- (void)setDeletable:(BOOL)deletable {
    _deletable = deletable;
    self.deleteButton.enabled = deletable;
    [self updateDeleteButtonVisibility];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTrackingArea) {
        [self removeTrackingArea:self.hoverTrackingArea];
    }
    self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                          options:(NSTrackingMouseEnteredAndExited
                                                                 | NSTrackingActiveAlways
                                                                 | NSTrackingInVisibleRect)
                                                            owner:self
                                                         userInfo:nil];
    [self addTrackingArea:self.hoverTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.hovered = YES;
    [self updateDeleteButtonVisibility];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.hovered = NO;
    [self updateDeleteButtonVisibility];
}

- (void)updateDeleteButtonVisibility {
    self.deleteButton.hidden = !(self.isDeletable && self.isHovered);
}

- (void)setDropTarget:(BOOL)dropTarget {
    if (_dropTarget == dropTarget) {
        return;
    }
    _dropTarget = dropTarget;
    self.needsDisplay = YES;
    [self displayIfNeeded];
}

- (void)resetCursorRects {
    [super resetCursorRects];
    if (self.isDraggable) {
        [self addCursorRect:self.bounds cursor:NSCursor.openHandCursor];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (self.isDropTarget) {
        NSColor *highlight = [NSColor.controlAccentColor colorWithAlphaComponent:0.16];
        [highlight setFill];
        NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
    }
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.isDraggable || !self.delegate) {
        return;
    }

    NSPoint initialPoint = event.locationInWindow;
    BOOL beganDragging = NO;
    self.window.acceptsMouseMovedEvents = YES;

    while (YES) {
        NSEvent *nextEvent = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (nextEvent.type == NSEventTypeLeftMouseUp) {
            if (beganDragging) {
                [self.delegate stockMenuItemViewDidEndDragging:self];
            }
            break;
        }

        NSPoint currentPoint = nextEvent.locationInWindow;
        CGFloat distance = hypot(currentPoint.x - initialPoint.x, currentPoint.y - initialPoint.y);
        if (!beganDragging && distance >= 3.0) {
            beganDragging = YES;
            self.alphaValue = 0.55;
            [NSCursor.closedHandCursor set];
            [self.delegate stockMenuItemViewDidBeginDragging:self];
        }
        if (beganDragging) {
            [self.delegate stockMenuItemView:self draggedToScreenPoint:NSEvent.mouseLocation];
        }
    }

    self.alphaValue = 1.0;
    [NSCursor.openHandCursor set];
}

- (void)requestDelete:(id)sender {
    (void)sender;
    if (self.isDeletable) {
        [self.delegate stockMenuItemViewDidRequestDelete:self];
    }
}

@end
