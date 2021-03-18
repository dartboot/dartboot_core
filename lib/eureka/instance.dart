import 'dart:io';

/// Eureka客户端的应用对象
class App {
  /// 应用名称
  final String name;

  /// 实例列表
  final List<Instance> instance;

  App({this.name, this.instance});

  /// 从json解析
  static App fromJson(json) {
    return App(
        name: json['name'],
        instance: List.from(json['instance'] ?? [])
            .map((j) => Instance.fromJson(j))
            .toList());
  }
}

/// Eureka客户端实例对象
///
/// @author luodongseu
class Instance {
  /// 实例ID
  final String instanceId;

  /// APP ID
  final String appId;

  /// 状态
  final String status;

  /// 端口号
  final int port;

  /// IP 地址
  final String ipAddr;

  /// 上下文路径
  final String contextPath;

  Instance(
      {this.instanceId,
      this.appId,
      this.port,
      this.status = 'UP',
      this.ipAddr,
      this.contextPath = '/'});

  /// 转换成JSON，补充部分字段
  dynamic toJson() async {
    return {
      "instanceId": '$instanceId',
      "app": appId,
      "ipAddr": ipAddr,
      'vipAddress': appId,
      'secureVipAddress': appId,
      "homePageUrl": contextPath ?? '/',
      "statusPageUrl": null,
      "healthCheckUrl": null,
      "secureHealthCheckUrl": null,
      "countryId": 1,
      "dataCenterInfo": {
        'name': 'MyOwn',
        '@class': 'com.netflix.appinfo.InstanceInfo\$DefaultDataCenterInfo'
      },
      "hostName": '${Platform.localHostname}',
      "status": status,
      "leaseInfo": null,
      "overridden_status": "UNKNOWN",
      "metadata": {'management.port': port},
      'port': {'\$': port, "@enabled": "true"}
    };
  }

  /// 从json解析
  static Instance fromJson(json) {
    return Instance(
        appId: json['app'],
        instanceId: json['instanceId'],
        ipAddr: json['ipAddr'],
        port: json['port']['\$']
    );
  }
}
