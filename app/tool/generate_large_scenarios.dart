import 'dart:convert';
import 'dart:io';

void main() {
  final seeds = <_ScenarioSeed>[
    _ScenarioSeed(
      id: 'cet4_exam',
      name: '大学英语四级考试',
      category: '考试',
      tag: '四级',
      background: '报名已经完成，需要按阶段准备听力、阅读、写作和翻译。',
      details: '准考证打印、耳机试音、入场证件和考试文具需要提前确认。',
      event1Title: '四级模拟考试',
      event1At: '2026-11-15T09:00:00+08:00',
      event2Title: '大学英语四级正式考试',
      event2At: '2026-12-19T09:00:00+08:00',
      todoTitle: '打印准考证并准备考试用品',
      todoDue: '2026-12-18T18:00:00+08:00',
      knowledge1Title: '四级考试时间节点与考场规则',
      knowledge1Body: '考试当天提前进入考场，携带身份证、准考证和调频耳机。',
      knowledge2Title: '四级冲刺资料与听力设备清单',
      knowledge2Body: '保留最近三年的真题、听力音频和错题整理，考前完成两次整套模拟。',
    ),
    _ScenarioSeed(
      id: 'driving_test',
      name: '驾照科目二考试',
      category: '考试',
      tag: '驾考',
      background: '需要完成场地训练、模拟考试和正式预约。',
      details: '倒车入库、侧方停车和坡道起步是重点，考试当天提前到场。',
      event1Title: '科目二模拟考试',
      event1At: '2026-10-18T08:30:00+08:00',
      event2Title: '科目二正式考试',
      event2At: '2026-10-25T08:00:00+08:00',
      todoTitle: '确认身份证和考试预约信息',
      todoDue: '2026-10-24T20:00:00+08:00',
      knowledge1Title: '科目二考试流程与扣分规则',
      knowledge1Body: '上车前调整座椅和后视镜，按语音提示完成项目，保持车速稳定。',
      knowledge2Title: '科目二训练重点与常见失误',
      knowledge2Body: '重点练习离合控制、点位判断和转向时机，减少中途停车。',
    ),
    _ScenarioSeed(
      id: 'japan_trip',
      name: '日本关西旅行',
      category: '旅行',
      tag: '日本',
      background: '计划前往大阪、京都和奈良，需要处理签证、交通和住宿。',
      details: '关西机场进出，使用地铁和近铁移动，提前购买交通卡和保险。',
      event1Title: '日本签证材料递交',
      event1At: '2026-10-15T10:00:00+08:00',
      event2Title: '大阪京都奈良旅行出发',
      event2At: '2026-12-05T08:00:00+08:00',
      todoTitle: '预订关西酒店和机场交通',
      todoDue: '2026-11-10T20:00:00+08:00',
      knowledge1Title: '关西旅行签证与入境准备',
      knowledge1Body: '准备护照、照片、行程单和资产证明，保存电子签证和酒店地址。',
      knowledge2Title: '大阪京都奈良交通与景点清单',
      knowledge2Body: '大阪使用御堂筋线，京都使用公交和地铁，奈良安排东大寺和春日大社。',
    ),
    _ScenarioSeed(
      id: 'home_renovation',
      name: '新房装修项目',
      category: '家庭',
      tag: '装修',
      background: '需要协调设计、水电、主材和软装，控制预算和施工节点。',
      details: '隐蔽工程验收后进入泥木阶段，家具家电需要提前测量尺寸。',
      event1Title: '装修水电隐蔽工程验收',
      event1At: '2026-10-20T14:00:00+08:00',
      event2Title: '装修主材进场与安装',
      event2At: '2026-11-08T09:00:00+08:00',
      todoTitle: '确认橱柜和浴室柜最终尺寸',
      todoDue: '2026-10-18T18:00:00+08:00',
      knowledge1Title: '装修隐蔽工程验收清单',
      knowledge1Body: '检查强弱电间距、线管固定、水管打压和防水闭水结果。',
      knowledge2Title: '主材进场与安装顺序',
      knowledge2Body: '瓷砖、门窗、橱柜和卫浴按施工顺序进场，避免交叉污染和尺寸冲突。',
    ),
    _ScenarioSeed(
      id: 'product_launch',
      name: '产品发布项目',
      category: '工作',
      tag: '产品',
      background: '需要在发布前完成测试、文档、定价和渠道准备。',
      details: '发布后收集反馈，安排客户沟通和版本复盘。',
      event1Title: '产品发布候选版本冻结',
      event1At: '2026-10-28T16:00:00+08:00',
      event2Title: '产品正式发布会',
      event2At: '2026-11-12T14:00:00+08:00',
      todoTitle: '完成发布说明和客服培训',
      todoDue: '2026-11-10T18:00:00+08:00',
      knowledge1Title: '产品发布检查清单',
      knowledge1Body: '覆盖功能冻结、回归测试、定价审批、市场素材和客服话术。',
      knowledge2Title: '发布风险与回滚预案',
      knowledge2Body: '准备灰度策略、监控指标、回滚脚本和紧急联系人。',
    ),
    _ScenarioSeed(
      id: 'health_check',
      name: '体检与复诊安排',
      category: '健康',
      tag: '体检',
      background: '需要完成预约、空腹检查、报告领取和异常指标复诊。',
      details: '整理既往报告和用药记录，复诊前确认需要携带的检查结果。',
      event1Title: '年度体检预约',
      event1At: '2026-10-22T07:30:00+08:00',
      event2Title: '体检异常指标复诊',
      event2At: '2026-11-03T09:30:00+08:00',
      todoTitle: '整理既往体检报告和用药清单',
      todoDue: '2026-11-02T20:00:00+08:00',
      knowledge1Title: '体检前准备与空腹要求',
      knowledge1Body: '体检前一晚清淡饮食，检查当天禁食禁水，携带身份证和既往报告。',
      knowledge2Title: '体检报告指标复查建议',
      knowledge2Body: '血常规、肝功能和影像异常需要结合医生意见安排复查。',
    ),
    _ScenarioSeed(
      id: 'parents_checkup',
      name: '父母体检安排',
      category: '家庭',
      tag: '父母',
      background: '为父母安排体检、交通接送和检查后随访。',
      details: '关注血压、血糖、心脏和骨密度项目，提前确认医保和预约流程。',
      event1Title: '父母体检陪同',
      event1At: '2026-11-01T07:00:00+08:00',
      event2Title: '父母体检结果解读',
      event2At: '2026-11-08T15:00:00+08:00',
      todoTitle: '确认父母体检项目和医保材料',
      todoDue: '2026-10-30T20:00:00+08:00',
      knowledge1Title: '中老年体检项目选择',
      knowledge1Body: '基础检查结合心脑血管、肿瘤筛查和骨密度项目。',
      knowledge2Title: '父母慢病用药与随访记录',
      knowledge2Body: '记录血压、血糖和用药变化，复诊时带给医生判断。',
    ),
    _ScenarioSeed(
      id: 'wedding_planning',
      name: '婚礼筹备',
      category: '家庭',
      tag: '婚礼',
      background: '需要确定酒店、婚纱、摄影、宾客名单和当天流程。',
      details: '预算优先分配酒店和摄影，提前完成试妆和流程彩排。',
      event1Title: '婚礼酒店与菜单确认',
      event1At: '2026-11-05T15:00:00+08:00',
      event2Title: '婚礼流程彩排',
      event2At: '2027-01-15T18:00:00+08:00',
      todoTitle: '确认宾客名单和桌数',
      todoDue: '2026-12-20T20:00:00+08:00',
      knowledge1Title: '婚礼筹备时间线',
      knowledge1Body: '提前一年定场地，半年定婚纱摄影，两个月确认宾客和桌数。',
      knowledge2Title: '婚礼当天流程与分工',
      knowledge2Body: '明确迎宾、仪式、敬酒和返程车辆负责人，准备备用方案。',
    ),
    _ScenarioSeed(
      id: 'marathon_training',
      name: '马拉松训练计划',
      category: '运动',
      tag: '马拉松',
      background: '为半程马拉松准备十六周训练，兼顾耐力、力量和恢复。',
      details: '控制周跑量增长，比赛前两周减量，关注睡眠和补给。',
      event1Title: '半程马拉松模拟跑',
      event1At: '2026-11-22T07:00:00+08:00',
      event2Title: '城市半程马拉松比赛',
      event2At: '2026-12-13T07:30:00+08:00',
      todoTitle: '准备比赛号码布和能量胶',
      todoDue: '2026-12-12T20:00:00+08:00',
      knowledge1Title: '半程马拉松训练周期',
      knowledge1Body: '每周安排轻松跑、节奏跑和长距离跑，逐步增加跑量。',
      knowledge2Title: '比赛补给与配速策略',
      knowledge2Body: '起跑避免过快，每五公里补水，按训练配速完成比赛。',
    ),
    _ScenarioSeed(
      id: 'graduate_exam',
      name: '考研报名与初试',
      category: '考试',
      tag: '考研',
      background: '需要完成预报名、正式报名、网上确认和初试准备。',
      details: '根据招生简章确认科目，整理证件照和学籍材料。',
      event1Title: '考研正式报名截止',
      event1At: '2026-10-25T22:00:00+08:00',
      event2Title: '研究生招生考试初试',
      event2At: '2026-12-26T08:30:00+08:00',
      todoTitle: '完成网上确认材料上传',
      todoDue: '2026-11-05T18:00:00+08:00',
      knowledge1Title: '考研报名材料与时间节点',
      knowledge1Body: '准备身份证、学历学籍材料、证件照和报考点要求文件。',
      knowledge2Title: '考研初试科目与复习安排',
      knowledge2Body: '按政治、英语、专业课拆分阶段目标，保留每周整套模拟。',
    ),
    _ScenarioSeed(
      id: 'company_annual',
      name: '公司年会项目',
      category: '工作',
      tag: '年会',
      background: '负责场地、节目、奖项、物料和现场执行。',
      details: '提前完成供应商确认和彩排，准备应急联系人。',
      event1Title: '年会节目彩排',
      event1At: '2026-12-18T18:00:00+08:00',
      event2Title: '公司年度晚宴',
      event2At: '2027-01-08T18:30:00+08:00',
      todoTitle: '确认年会奖品和采购预算',
      todoDue: '2026-12-10T18:00:00+08:00',
      knowledge1Title: '年会执行清单',
      knowledge1Body: '覆盖场地方、餐饮、音响、节目、抽奖和签到流程。',
      knowledge2Title: '年会供应商与预算控制',
      knowledge2Body: '分项确认报价、付款节点和备用供应商，保留总预算缓冲。',
    ),
    _ScenarioSeed(
      id: 'moving_home',
      name: '搬家与地址迁移',
      category: '生活',
      tag: '搬家',
      background: '需要安排打包、搬家公司、宽带迁移和地址更新。',
      details: '重要证件和贵重物品单独携带，旧房完成水电和物业交接。',
      event1Title: '旧房物业交接',
      event1At: '2026-10-30T10:00:00+08:00',
      event2Title: '正式搬家日',
      event2At: '2026-10-31T08:00:00+08:00',
      todoTitle: '更新快递、银行和社保地址',
      todoDue: '2026-11-05T18:00:00+08:00',
      knowledge1Title: '搬家打包与物品分类清单',
      knowledge1Body: '按房间和物品类型标记纸箱，重要文件随身携带。',
      knowledge2Title: '搬家后地址变更清单',
      knowledge2Body: '更新银行、快递、保险、水电网和常用账号地址。',
    ),
    _ScenarioSeed(
      id: 'family_finance',
      name: '家庭财务规划',
      category: '财务',
      tag: '家庭财务',
      background: '梳理收入支出、应急资金、保险和长期储蓄目标。',
      details: '每年复盘资产配置，避免单一风险，保留三到六个月应急金。',
      event1Title: '家庭年度预算复盘',
      event1At: '2026-11-20T20:00:00+08:00',
      event2Title: '家庭保险与储蓄规划会',
      event2At: '2026-12-06T15:00:00+08:00',
      todoTitle: '整理家庭资产和负债清单',
      todoDue: '2026-11-18T20:00:00+08:00',
      knowledge1Title: '家庭应急资金配置原则',
      knowledge1Body: '保留三到六个月固定支出，放在高流动性低风险账户。',
      knowledge2Title: '家庭保险配置检查',
      knowledge2Body: '优先医疗、重疾和意外保障，避免重复投保和过度保障。',
    ),
    _ScenarioSeed(
      id: 'pet_surgery',
      name: '宠物绝育与疫苗',
      category: '生活',
      tag: '宠物',
      background: '安排宠物术前检查、绝育手术、疫苗和术后复查。',
      details: '术前禁食禁水，准备伊丽莎白圈和术后护理用品。',
      event1Title: '宠物术前检查',
      event1At: '2026-10-24T10:00:00+08:00',
      event2Title: '宠物绝育手术',
      event2At: '2026-10-26T09:00:00+08:00',
      todoTitle: '准备宠物术后护理用品',
      todoDue: '2026-10-25T20:00:00+08:00',
      knowledge1Title: '宠物绝育术前准备',
      knowledge1Body: '按医嘱禁食禁水，携带疫苗本和既往检查报告。',
      knowledge2Title: '宠物术后护理与复查',
      knowledge2Body: '观察食欲、伤口和排泄，按时用药并限制剧烈活动。',
    ),
    _ScenarioSeed(
      id: 'car_maintenance',
      name: '汽车年检与保养',
      category: '生活',
      tag: '汽车',
      background: '需要处理年检、保养、保险续费和常用证件更新。',
      details: '检查轮胎、刹车、电瓶和机油，准备行驶证和保险材料。',
      event1Title: '汽车年度保养',
      event1At: '2026-11-16T10:00:00+08:00',
      event2Title: '汽车年检办理',
      event2At: '2026-11-23T09:00:00+08:00',
      todoTitle: '确认保险续费和年检材料',
      todoDue: '2026-11-20T18:00:00+08:00',
      knowledge1Title: '汽车年检材料与流程',
      knowledge1Body: '准备行驶证、身份证、保险单，提前处理违章和车辆故障。',
      knowledge2Title: '汽车年度保养检查项',
      knowledge2Body: '检查机油、轮胎、刹车、电瓶和空调滤芯，记录保养里程。',
    ),
    _ScenarioSeed(
      id: 'uk_visa',
      name: '英国访问签证申请',
      category: '旅行',
      tag: '英国签证',
      background: '准备签证材料、预约录指纹、提交护照并跟踪结果。',
      details: '资金证明、行程和邀请函需要保持一致，保存递签回执。',
      event1Title: '英国签证中心递交材料',
      event1At: '2026-11-04T09:30:00+08:00',
      event2Title: '英国访问行程出发',
      event2At: '2027-01-20T10:00:00+08:00',
      todoTitle: '准备银行流水和行程单',
      todoDue: '2026-11-01T20:00:00+08:00',
      knowledge1Title: '英国访问签证材料清单',
      knowledge1Body: '准备护照、照片、申请表、资金证明、行程和在职证明。',
      knowledge2Title: '英国入境与旅行准备',
      knowledge2Body: '保存签证页、住宿地址和返程机票，准备转换插头和旅行保险。',
    ),
    _ScenarioSeed(
      id: 'startup_pitch',
      name: '创业项目路演',
      category: '工作',
      tag: '创业',
      background: '准备商业计划、财务模型、产品演示和投资人沟通。',
      details: '路演重点是问题、方案、市场、团队和融资用途，提前完成彩排。',
      event1Title: '创业项目路演彩排',
      event1At: '2026-11-06T14:00:00+08:00',
      event2Title: '投资人路演日',
      event2At: '2026-11-18T10:00:00+08:00',
      todoTitle: '完成财务模型和路演材料',
      todoDue: '2026-11-15T18:00:00+08:00',
      knowledge1Title: '创业路演结构',
      knowledge1Body: '用问题、产品、市场、商业模式、团队和融资计划组织内容。',
      knowledge2Title: '投资人常见问题与数据准备',
      knowledge2Body: '准备获客成本、留存、毛利率、竞争壁垒和资金使用计划。',
    ),
    _ScenarioSeed(
      id: 'volunteer_event',
      name: '社区志愿者活动',
      category: '公益',
      tag: '志愿者',
      background: '组织物资、报名、培训、现场服务和活动复盘。',
      details: '确认服务对象、集合时间和安全要求，准备志愿证明。',
      event1Title: '志愿者岗前培训',
      event1At: '2026-10-27T19:00:00+08:00',
      event2Title: '社区志愿服务日',
      event2At: '2026-11-02T08:30:00+08:00',
      todoTitle: '确认志愿者名单和物资',
      todoDue: '2026-11-01T18:00:00+08:00',
      knowledge1Title: '志愿者活动安全与服务规范',
      knowledge1Body: '统一着装、准时集合、尊重服务对象并遵守现场安全要求。',
      knowledge2Title: '社区志愿物资清单',
      knowledge2Body: '准备饮用水、急救包、手套、签到表和活动记录设备。',
    ),
    _ScenarioSeed(
      id: 'semester_thesis',
      name: '学期论文与答辩',
      category: '学习',
      tag: '论文',
      background: '完成选题、文献综述、实验、论文初稿和答辩准备。',
      details: '严格记录引用，按导师意见迭代修改并提前完成查重。',
      event1Title: '论文中期检查',
      event1At: '2026-11-12T15:00:00+08:00',
      event2Title: '学期论文答辩',
      event2At: '2026-12-28T09:00:00+08:00',
      todoTitle: '完成论文初稿和查重',
      todoDue: '2026-12-15T20:00:00+08:00',
      knowledge1Title: '论文写作与引用规范',
      knowledge1Body: '按学校格式整理引用和参考文献，保留文献原文和检索记录。',
      knowledge2Title: '论文答辩准备清单',
      knowledge2Body: '准备研究问题、方法、结果、创新点和常见问题回答。',
    ),
    _ScenarioSeed(
      id: 'spring_festival',
      name: '家庭春节聚会',
      category: '家庭',
      tag: '春节',
      background: '协调返乡、年夜饭、礼物、住宿和家庭活动。',
      details: '提前确认人数、忌口和交通，准备长辈礼物和儿童活动。',
      event1Title: '春节返乡出发',
      event1At: '2027-02-02T08:00:00+08:00',
      event2Title: '家庭年夜饭',
      event2At: '2027-02-06T18:00:00+08:00',
      todoTitle: '确认返乡人数和年货清单',
      todoDue: '2027-01-28T20:00:00+08:00',
      knowledge1Title: '春节返乡交通与行李准备',
      knowledge1Body: '提前购票，准备证件、保暖衣物、常用药和长辈礼物。',
      knowledge2Title: '年夜饭菜单与家庭活动安排',
      knowledge2Body: '兼顾长辈口味和儿童需求，准备年夜饭菜单、游戏和拍照环节。',
    ),
  ];

  if (seeds.length != 20) {
    throw StateError('Expected 20 scenario seeds, got ${seeds.length}');
  }
  final scenarios = <Map<String, Object?>>[];
  for (var index = 0; index < seeds.length; index++) {
    scenarios.add(_scenario(seeds[index], index + 1));
  }

  final output = const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'generatedAt': '2026-10-05T23:00:00+08:00',
    'scenarios': scenarios,
  });
  final jsonFile = File('test/fixtures/large_scenario_20_cases.json');
  jsonFile.parent.createSync(recursive: true);
  jsonFile.writeAsStringSync('$output\n');

  final dartFile = File('test/large_scenario_20_cases.g.dart');
  dartFile.writeAsStringSync(
    '// Generated by tool/generate_large_scenarios.dart.\n'
    'const largeScenarioMaps = <Map<String, Object?>>'
    '${const JsonEncoder.withIndent('  ').convert(scenarios)};\n',
  );
  stdout.writeln(
    'Wrote ${scenarios.length} scenarios to ${jsonFile.path} and ${dartFile.path}',
  );
}

Map<String, Object?> _scenario(_ScenarioSeed seed, int sequence) {
  final event1Start = _at(seed.event1At);
  final event2Start = _at(seed.event2At);
  final todoDue = _at(seed.todoDue);
  final tags = [seed.category, seed.tag];

  return {
    'id': 'large_scenario_${sequence.toString().padLeft(3, '0')}',
    'key': seed.id,
    'name': seed.name,
    'category': seed.category,
    'summary': seed.background,
    'messages': [
      {
        'text':
            '我正在准备${seed.name}。${seed.background} '
            '先安排${seed.event1Title}，时间${_friendly(event1Start)}；'
            '${seed.todoTitle}最晚在${_friendly(todoDue)}前完成；'
            '再记录${seed.knowledge1Title}。',
        'assistant': '已整理${seed.name}的第一批事项和知识。',
        'calls': [
          _matter(seed, tags),
          _event(seed.event1Title, seed.background, event1Start, tags),
          _todo(seed.todoTitle, todoDue, tags),
          _knowledge(seed.knowledge1Title, seed.knowledge1Body, tags),
        ],
      },
      {
        'text':
            '补充${seed.name}的第二阶段。${seed.details} '
            '${seed.event2Title}安排在${_friendly(event2Start)}，'
            '同时整理${seed.knowledge2Title}。',
        'assistant': '已补齐${seed.name}的第二批事项和知识。',
        'calls': [
          _event(seed.event2Title, seed.details, event2Start, tags),
          _knowledge(seed.knowledge2Title, seed.knowledge2Body, tags),
        ],
      },
    ],
  };
}

Map<String, Object?> _matter(_ScenarioSeed seed, List<String> tags) {
  return {
    'type': 'matter',
    'title': seed.name,
    'body': seed.background,
    'confidence': 0.96,
    'sensitive': false,
    'tags': tags,
    'expect': 'created',
  };
}

Map<String, Object?> _event(
  String title,
  String body,
  DateTime start,
  List<String> tags,
) {
  return {
    'type': 'event',
    'title': title,
    'body': body,
    'confidence': 0.95,
    'sensitive': false,
    'tags': tags,
    'start': start.toIso8601String(),
    'end': start.add(const Duration(hours: 2)).toIso8601String(),
    'all_day': false,
    'expect': 'created',
  };
}

Map<String, Object?> _todo(String title, DateTime due, List<String> tags) {
  return {
    'type': 'todo',
    'title': title,
    'body': '在截止时间前完成：$title',
    'confidence': 0.94,
    'sensitive': false,
    'tags': tags,
    'due': due.toIso8601String(),
    'expect': 'created',
  };
}

Map<String, Object?> _knowledge(String title, String body, List<String> tags) {
  return {
    'type': 'knowledge',
    'title': title,
    'body': body,
    'confidence': 0.93,
    'sensitive': false,
    'tags': tags,
    'expect': 'created',
  };
}

DateTime _at(String value) => DateTime.parse(value);

String _friendly(DateTime value) {
  final local = value.toUtc().add(const Duration(hours: 8));
  final hour = local.hour;
  final period = hour < 6
      ? '凌晨'
      : hour < 12
      ? '上午'
      : hour < 18
      ? '下午'
      : '晚上';
  final displayHour = hour > 12 ? hour - 12 : hour;
  final minute = local.minute == 0
      ? ''
      : '${local.minute.toString().padLeft(2, '0')}分';
  return '${local.month}月${local.day}日$period$displayHour点$minute';
}

class _ScenarioSeed {
  const _ScenarioSeed({
    required this.id,
    required this.name,
    required this.category,
    required this.tag,
    required this.background,
    required this.details,
    required this.event1Title,
    required this.event1At,
    required this.event2Title,
    required this.event2At,
    required this.todoTitle,
    required this.todoDue,
    required this.knowledge1Title,
    required this.knowledge1Body,
    required this.knowledge2Title,
    required this.knowledge2Body,
  });

  final String id;
  final String name;
  final String category;
  final String tag;
  final String background;
  final String details;
  final String event1Title;
  final String event1At;
  final String event2Title;
  final String event2At;
  final String todoTitle;
  final String todoDue;
  final String knowledge1Title;
  final String knowledge1Body;
  final String knowledge2Title;
  final String knowledge2Body;
}
