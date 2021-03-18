import 'dart:async';
import 'dart:io';

import '../annotation/annotation.dart';
import 'client.dart';

/// 关闭的延时
const Duration shutdownDelay = Duration(seconds: 10);

/// Eureka客户端的开放接口
///
/// 1. 关闭客户端
/// 2. 注册客户端
///
/// @author luodongseu
@RestController()
class EurekaClientEndpoint {
  /// 关闭订阅
  StreamSubscription _shutdownSub;

  /// 健康度检查
  @Get('/health')
  void health() {
    print('health!');
  }

  /// 关闭应用
  @Post('/shutdown')
  void shutdownAndWaitWakeUp() {
    EurekaClient.instance.down();
    _shutdownSub?.cancel();
    _shutdownSub = Future.delayed(shutdownDelay).asStream().listen((d) {
      print('After $shutdownDelay no wake up call, application exits now.');
      exit(0);
    });
  }

  /// 唤醒应用
  @Post('/register')
  void wakeUp() {
    _shutdownSub?.cancel();
    EurekaClient.instance.up();
  }
}
