//
//  ViewController.h
//  iOS Sample
//
//  Created by Abdullah Selek on 13/01/2017.
//  Copyright © 2017 Abdullah Selek. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Merhaba/Merhaba.h>

@interface ViewController : UIViewController<MRBServerDelegate>

@property (nonatomic) MRBServer *server;

@end
