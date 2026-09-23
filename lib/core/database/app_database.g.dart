// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SavedPlacesTable extends SavedPlaces
    with TableInfo<$SavedPlacesTable, SavedPlace> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedPlacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 100),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _addressMeta =
      const VerificationMeta('address');
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
      'address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('favorite'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, latitude, longitude, address, category, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_places';
  @override
  VerificationContext validateIntegrity(Insertable<SavedPlace> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('address')) {
      context.handle(_addressMeta,
          address.isAcceptableOrUnknown(data['address']!, _addressMeta));
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedPlace map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedPlace(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      address: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}address']),
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $SavedPlacesTable createAlias(String alias) {
    return $SavedPlacesTable(attachedDatabase, alias);
  }
}

class SavedPlace extends DataClass implements Insertable<SavedPlace> {
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final String category;
  final DateTime createdAt;
  const SavedPlace(
      {required this.id,
      required this.name,
      required this.latitude,
      required this.longitude,
      this.address,
      required this.category,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    map['category'] = Variable<String>(category);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SavedPlacesCompanion toCompanion(bool nullToAbsent) {
    return SavedPlacesCompanion(
      id: Value(id),
      name: Value(name),
      latitude: Value(latitude),
      longitude: Value(longitude),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      category: Value(category),
      createdAt: Value(createdAt),
    );
  }

  factory SavedPlace.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedPlace(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      address: serializer.fromJson<String?>(json['address']),
      category: serializer.fromJson<String>(json['category']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'address': serializer.toJson<String?>(address),
      'category': serializer.toJson<String>(category),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SavedPlace copyWith(
          {int? id,
          String? name,
          double? latitude,
          double? longitude,
          Value<String?> address = const Value.absent(),
          String? category,
          DateTime? createdAt}) =>
      SavedPlace(
        id: id ?? this.id,
        name: name ?? this.name,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        address: address.present ? address.value : this.address,
        category: category ?? this.category,
        createdAt: createdAt ?? this.createdAt,
      );
  SavedPlace copyWithCompanion(SavedPlacesCompanion data) {
    return SavedPlace(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      address: data.address.present ? data.address.value : this.address,
      category: data.category.present ? data.category.value : this.category,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedPlace(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('address: $address, ')
          ..write('category: $category, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, latitude, longitude, address, category, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedPlace &&
          other.id == this.id &&
          other.name == this.name &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.address == this.address &&
          other.category == this.category &&
          other.createdAt == this.createdAt);
}

class SavedPlacesCompanion extends UpdateCompanion<SavedPlace> {
  final Value<int> id;
  final Value<String> name;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<String?> address;
  final Value<String> category;
  final Value<DateTime> createdAt;
  const SavedPlacesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.address = const Value.absent(),
    this.category = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SavedPlacesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required double latitude,
    required double longitude,
    this.address = const Value.absent(),
    this.category = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : name = Value(name),
        latitude = Value(latitude),
        longitude = Value(longitude);
  static Insertable<SavedPlace> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? address,
    Expression<String>? category,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (address != null) 'address': address,
      if (category != null) 'category': category,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SavedPlacesCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<String?>? address,
      Value<String>? category,
      Value<DateTime>? createdAt}) {
    return SavedPlacesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedPlacesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('address: $address, ')
          ..write('category: $category, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $RouteHistoryTable extends RouteHistory
    with TableInfo<$RouteHistoryTable, RouteHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RouteHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _startLatMeta =
      const VerificationMeta('startLat');
  @override
  late final GeneratedColumn<double> startLat = GeneratedColumn<double>(
      'start_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _startLngMeta =
      const VerificationMeta('startLng');
  @override
  late final GeneratedColumn<double> startLng = GeneratedColumn<double>(
      'start_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _endLatMeta = const VerificationMeta('endLat');
  @override
  late final GeneratedColumn<double> endLat = GeneratedColumn<double>(
      'end_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _endLngMeta = const VerificationMeta('endLng');
  @override
  late final GeneratedColumn<double> endLng = GeneratedColumn<double>(
      'end_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _endLabelMeta =
      const VerificationMeta('endLabel');
  @override
  late final GeneratedColumn<String> endLabel = GeneratedColumn<String>(
      'end_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, startLat, startLng, endLat, endLng, endLabel, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'route_history';
  @override
  VerificationContext validateIntegrity(Insertable<RouteHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('start_lat')) {
      context.handle(_startLatMeta,
          startLat.isAcceptableOrUnknown(data['start_lat']!, _startLatMeta));
    } else if (isInserting) {
      context.missing(_startLatMeta);
    }
    if (data.containsKey('start_lng')) {
      context.handle(_startLngMeta,
          startLng.isAcceptableOrUnknown(data['start_lng']!, _startLngMeta));
    } else if (isInserting) {
      context.missing(_startLngMeta);
    }
    if (data.containsKey('end_lat')) {
      context.handle(_endLatMeta,
          endLat.isAcceptableOrUnknown(data['end_lat']!, _endLatMeta));
    } else if (isInserting) {
      context.missing(_endLatMeta);
    }
    if (data.containsKey('end_lng')) {
      context.handle(_endLngMeta,
          endLng.isAcceptableOrUnknown(data['end_lng']!, _endLngMeta));
    } else if (isInserting) {
      context.missing(_endLngMeta);
    }
    if (data.containsKey('end_label')) {
      context.handle(_endLabelMeta,
          endLabel.isAcceptableOrUnknown(data['end_label']!, _endLabelMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RouteHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RouteHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      startLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}start_lat'])!,
      startLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}start_lng'])!,
      endLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}end_lat'])!,
      endLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}end_lng'])!,
      endLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}end_label']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $RouteHistoryTable createAlias(String alias) {
    return $RouteHistoryTable(attachedDatabase, alias);
  }
}

class RouteHistoryData extends DataClass
    implements Insertable<RouteHistoryData> {
  final int id;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final String? endLabel;
  final DateTime createdAt;
  const RouteHistoryData(
      {required this.id,
      required this.startLat,
      required this.startLng,
      required this.endLat,
      required this.endLng,
      this.endLabel,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['start_lat'] = Variable<double>(startLat);
    map['start_lng'] = Variable<double>(startLng);
    map['end_lat'] = Variable<double>(endLat);
    map['end_lng'] = Variable<double>(endLng);
    if (!nullToAbsent || endLabel != null) {
      map['end_label'] = Variable<String>(endLabel);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RouteHistoryCompanion toCompanion(bool nullToAbsent) {
    return RouteHistoryCompanion(
      id: Value(id),
      startLat: Value(startLat),
      startLng: Value(startLng),
      endLat: Value(endLat),
      endLng: Value(endLng),
      endLabel: endLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(endLabel),
      createdAt: Value(createdAt),
    );
  }

  factory RouteHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RouteHistoryData(
      id: serializer.fromJson<int>(json['id']),
      startLat: serializer.fromJson<double>(json['startLat']),
      startLng: serializer.fromJson<double>(json['startLng']),
      endLat: serializer.fromJson<double>(json['endLat']),
      endLng: serializer.fromJson<double>(json['endLng']),
      endLabel: serializer.fromJson<String?>(json['endLabel']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'startLat': serializer.toJson<double>(startLat),
      'startLng': serializer.toJson<double>(startLng),
      'endLat': serializer.toJson<double>(endLat),
      'endLng': serializer.toJson<double>(endLng),
      'endLabel': serializer.toJson<String?>(endLabel),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  RouteHistoryData copyWith(
          {int? id,
          double? startLat,
          double? startLng,
          double? endLat,
          double? endLng,
          Value<String?> endLabel = const Value.absent(),
          DateTime? createdAt}) =>
      RouteHistoryData(
        id: id ?? this.id,
        startLat: startLat ?? this.startLat,
        startLng: startLng ?? this.startLng,
        endLat: endLat ?? this.endLat,
        endLng: endLng ?? this.endLng,
        endLabel: endLabel.present ? endLabel.value : this.endLabel,
        createdAt: createdAt ?? this.createdAt,
      );
  RouteHistoryData copyWithCompanion(RouteHistoryCompanion data) {
    return RouteHistoryData(
      id: data.id.present ? data.id.value : this.id,
      startLat: data.startLat.present ? data.startLat.value : this.startLat,
      startLng: data.startLng.present ? data.startLng.value : this.startLng,
      endLat: data.endLat.present ? data.endLat.value : this.endLat,
      endLng: data.endLng.present ? data.endLng.value : this.endLng,
      endLabel: data.endLabel.present ? data.endLabel.value : this.endLabel,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RouteHistoryData(')
          ..write('id: $id, ')
          ..write('startLat: $startLat, ')
          ..write('startLng: $startLng, ')
          ..write('endLat: $endLat, ')
          ..write('endLng: $endLng, ')
          ..write('endLabel: $endLabel, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, startLat, startLng, endLat, endLng, endLabel, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RouteHistoryData &&
          other.id == this.id &&
          other.startLat == this.startLat &&
          other.startLng == this.startLng &&
          other.endLat == this.endLat &&
          other.endLng == this.endLng &&
          other.endLabel == this.endLabel &&
          other.createdAt == this.createdAt);
}

class RouteHistoryCompanion extends UpdateCompanion<RouteHistoryData> {
  final Value<int> id;
  final Value<double> startLat;
  final Value<double> startLng;
  final Value<double> endLat;
  final Value<double> endLng;
  final Value<String?> endLabel;
  final Value<DateTime> createdAt;
  const RouteHistoryCompanion({
    this.id = const Value.absent(),
    this.startLat = const Value.absent(),
    this.startLng = const Value.absent(),
    this.endLat = const Value.absent(),
    this.endLng = const Value.absent(),
    this.endLabel = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RouteHistoryCompanion.insert({
    this.id = const Value.absent(),
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    this.endLabel = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : startLat = Value(startLat),
        startLng = Value(startLng),
        endLat = Value(endLat),
        endLng = Value(endLng);
  static Insertable<RouteHistoryData> custom({
    Expression<int>? id,
    Expression<double>? startLat,
    Expression<double>? startLng,
    Expression<double>? endLat,
    Expression<double>? endLng,
    Expression<String>? endLabel,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startLat != null) 'start_lat': startLat,
      if (startLng != null) 'start_lng': startLng,
      if (endLat != null) 'end_lat': endLat,
      if (endLng != null) 'end_lng': endLng,
      if (endLabel != null) 'end_label': endLabel,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RouteHistoryCompanion copyWith(
      {Value<int>? id,
      Value<double>? startLat,
      Value<double>? startLng,
      Value<double>? endLat,
      Value<double>? endLng,
      Value<String?>? endLabel,
      Value<DateTime>? createdAt}) {
    return RouteHistoryCompanion(
      id: id ?? this.id,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      endLat: endLat ?? this.endLat,
      endLng: endLng ?? this.endLng,
      endLabel: endLabel ?? this.endLabel,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (startLat.present) {
      map['start_lat'] = Variable<double>(startLat.value);
    }
    if (startLng.present) {
      map['start_lng'] = Variable<double>(startLng.value);
    }
    if (endLat.present) {
      map['end_lat'] = Variable<double>(endLat.value);
    }
    if (endLng.present) {
      map['end_lng'] = Variable<double>(endLng.value);
    }
    if (endLabel.present) {
      map['end_label'] = Variable<String>(endLabel.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RouteHistoryCompanion(')
          ..write('id: $id, ')
          ..write('startLat: $startLat, ')
          ..write('startLng: $startLng, ')
          ..write('endLat: $endLat, ')
          ..write('endLng: $endLng, ')
          ..write('endLabel: $endLabel, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(Insertable<AppSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory AppSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) => AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LastKnownLocationTable extends LastKnownLocation
    with TableInfo<$LastKnownLocationTable, LastKnownLocationData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LastKnownLocationTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _headingMeta =
      const VerificationMeta('heading');
  @override
  late final GeneratedColumn<double> heading = GeneratedColumn<double>(
      'heading', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _speedKmhMeta =
      const VerificationMeta('speedKmh');
  @override
  late final GeneratedColumn<double> speedKmh = GeneratedColumn<double>(
      'speed_kmh', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _accuracyMeta =
      const VerificationMeta('accuracy');
  @override
  late final GeneratedColumn<double> accuracy = GeneratedColumn<double>(
      'accuracy', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, latitude, longitude, heading, speedKmh, accuracy, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'last_known_location';
  @override
  VerificationContext validateIntegrity(
      Insertable<LastKnownLocationData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('heading')) {
      context.handle(_headingMeta,
          heading.isAcceptableOrUnknown(data['heading']!, _headingMeta));
    }
    if (data.containsKey('speed_kmh')) {
      context.handle(_speedKmhMeta,
          speedKmh.isAcceptableOrUnknown(data['speed_kmh']!, _speedKmhMeta));
    }
    if (data.containsKey('accuracy')) {
      context.handle(_accuracyMeta,
          accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LastKnownLocationData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LastKnownLocationData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      heading: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}heading']),
      speedKmh: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}speed_kmh']),
      accuracy: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}accuracy']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LastKnownLocationTable createAlias(String alias) {
    return $LastKnownLocationTable(attachedDatabase, alias);
  }
}

class LastKnownLocationData extends DataClass
    implements Insertable<LastKnownLocationData> {
  final int id;
  final double latitude;
  final double longitude;
  final double? heading;
  final double? speedKmh;
  final double? accuracy;
  final DateTime updatedAt;
  const LastKnownLocationData(
      {required this.id,
      required this.latitude,
      required this.longitude,
      this.heading,
      this.speedKmh,
      this.accuracy,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || heading != null) {
      map['heading'] = Variable<double>(heading);
    }
    if (!nullToAbsent || speedKmh != null) {
      map['speed_kmh'] = Variable<double>(speedKmh);
    }
    if (!nullToAbsent || accuracy != null) {
      map['accuracy'] = Variable<double>(accuracy);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LastKnownLocationCompanion toCompanion(bool nullToAbsent) {
    return LastKnownLocationCompanion(
      id: Value(id),
      latitude: Value(latitude),
      longitude: Value(longitude),
      heading: heading == null && nullToAbsent
          ? const Value.absent()
          : Value(heading),
      speedKmh: speedKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(speedKmh),
      accuracy: accuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracy),
      updatedAt: Value(updatedAt),
    );
  }

  factory LastKnownLocationData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LastKnownLocationData(
      id: serializer.fromJson<int>(json['id']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      heading: serializer.fromJson<double?>(json['heading']),
      speedKmh: serializer.fromJson<double?>(json['speedKmh']),
      accuracy: serializer.fromJson<double?>(json['accuracy']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'heading': serializer.toJson<double?>(heading),
      'speedKmh': serializer.toJson<double?>(speedKmh),
      'accuracy': serializer.toJson<double?>(accuracy),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LastKnownLocationData copyWith(
          {int? id,
          double? latitude,
          double? longitude,
          Value<double?> heading = const Value.absent(),
          Value<double?> speedKmh = const Value.absent(),
          Value<double?> accuracy = const Value.absent(),
          DateTime? updatedAt}) =>
      LastKnownLocationData(
        id: id ?? this.id,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        heading: heading.present ? heading.value : this.heading,
        speedKmh: speedKmh.present ? speedKmh.value : this.speedKmh,
        accuracy: accuracy.present ? accuracy.value : this.accuracy,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LastKnownLocationData copyWithCompanion(LastKnownLocationCompanion data) {
    return LastKnownLocationData(
      id: data.id.present ? data.id.value : this.id,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      heading: data.heading.present ? data.heading.value : this.heading,
      speedKmh: data.speedKmh.present ? data.speedKmh.value : this.speedKmh,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LastKnownLocationData(')
          ..write('id: $id, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('heading: $heading, ')
          ..write('speedKmh: $speedKmh, ')
          ..write('accuracy: $accuracy, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, latitude, longitude, heading, speedKmh, accuracy, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LastKnownLocationData &&
          other.id == this.id &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.heading == this.heading &&
          other.speedKmh == this.speedKmh &&
          other.accuracy == this.accuracy &&
          other.updatedAt == this.updatedAt);
}

class LastKnownLocationCompanion
    extends UpdateCompanion<LastKnownLocationData> {
  final Value<int> id;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> heading;
  final Value<double?> speedKmh;
  final Value<double?> accuracy;
  final Value<DateTime> updatedAt;
  const LastKnownLocationCompanion({
    this.id = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.heading = const Value.absent(),
    this.speedKmh = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  LastKnownLocationCompanion.insert({
    this.id = const Value.absent(),
    required double latitude,
    required double longitude,
    this.heading = const Value.absent(),
    this.speedKmh = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : latitude = Value(latitude),
        longitude = Value(longitude);
  static Insertable<LastKnownLocationData> custom({
    Expression<int>? id,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? heading,
    Expression<double>? speedKmh,
    Expression<double>? accuracy,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (heading != null) 'heading': heading,
      if (speedKmh != null) 'speed_kmh': speedKmh,
      if (accuracy != null) 'accuracy': accuracy,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  LastKnownLocationCompanion copyWith(
      {Value<int>? id,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<double?>? heading,
      Value<double?>? speedKmh,
      Value<double?>? accuracy,
      Value<DateTime>? updatedAt}) {
    return LastKnownLocationCompanion(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      heading: heading ?? this.heading,
      speedKmh: speedKmh ?? this.speedKmh,
      accuracy: accuracy ?? this.accuracy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (heading.present) {
      map['heading'] = Variable<double>(heading.value);
    }
    if (speedKmh.present) {
      map['speed_kmh'] = Variable<double>(speedKmh.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<double>(accuracy.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LastKnownLocationCompanion(')
          ..write('id: $id, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('heading: $heading, ')
          ..write('speedKmh: $speedKmh, ')
          ..write('accuracy: $accuracy, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $SearchHistoryTable extends SearchHistory
    with TableInfo<$SearchHistoryTable, SearchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
      'query', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _subtitleMeta =
      const VerificationMeta('subtitle');
  @override
  late final GeneratedColumn<String> subtitle = GeneratedColumn<String>(
      'subtitle', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _isOfflineMeta =
      const VerificationMeta('isOffline');
  @override
  late final GeneratedColumn<bool> isOffline = GeneratedColumn<bool>(
      'is_offline', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_offline" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _searchedAtMeta =
      const VerificationMeta('searchedAt');
  @override
  late final GeneratedColumn<DateTime> searchedAt = GeneratedColumn<DateTime>(
      'searched_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, query, title, subtitle, latitude, longitude, isOffline, searchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_history';
  @override
  VerificationContext validateIntegrity(Insertable<SearchHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('query')) {
      context.handle(
          _queryMeta, query.isAcceptableOrUnknown(data['query']!, _queryMeta));
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('subtitle')) {
      context.handle(_subtitleMeta,
          subtitle.isAcceptableOrUnknown(data['subtitle']!, _subtitleMeta));
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('is_offline')) {
      context.handle(_isOfflineMeta,
          isOffline.isAcceptableOrUnknown(data['is_offline']!, _isOfflineMeta));
    }
    if (data.containsKey('searched_at')) {
      context.handle(
          _searchedAtMeta,
          searchedAt.isAcceptableOrUnknown(
              data['searched_at']!, _searchedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SearchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      query: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}query'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      subtitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subtitle']),
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      isOffline: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_offline'])!,
      searchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}searched_at'])!,
    );
  }

  @override
  $SearchHistoryTable createAlias(String alias) {
    return $SearchHistoryTable(attachedDatabase, alias);
  }
}

class SearchHistoryData extends DataClass
    implements Insertable<SearchHistoryData> {
  final int id;
  final String query;
  final String title;
  final String? subtitle;
  final double latitude;
  final double longitude;
  final bool isOffline;
  final DateTime searchedAt;
  const SearchHistoryData(
      {required this.id,
      required this.query,
      required this.title,
      this.subtitle,
      required this.latitude,
      required this.longitude,
      required this.isOffline,
      required this.searchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['query'] = Variable<String>(query);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || subtitle != null) {
      map['subtitle'] = Variable<String>(subtitle);
    }
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['is_offline'] = Variable<bool>(isOffline);
    map['searched_at'] = Variable<DateTime>(searchedAt);
    return map;
  }

  SearchHistoryCompanion toCompanion(bool nullToAbsent) {
    return SearchHistoryCompanion(
      id: Value(id),
      query: Value(query),
      title: Value(title),
      subtitle: subtitle == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitle),
      latitude: Value(latitude),
      longitude: Value(longitude),
      isOffline: Value(isOffline),
      searchedAt: Value(searchedAt),
    );
  }

  factory SearchHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchHistoryData(
      id: serializer.fromJson<int>(json['id']),
      query: serializer.fromJson<String>(json['query']),
      title: serializer.fromJson<String>(json['title']),
      subtitle: serializer.fromJson<String?>(json['subtitle']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      isOffline: serializer.fromJson<bool>(json['isOffline']),
      searchedAt: serializer.fromJson<DateTime>(json['searchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'query': serializer.toJson<String>(query),
      'title': serializer.toJson<String>(title),
      'subtitle': serializer.toJson<String?>(subtitle),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'isOffline': serializer.toJson<bool>(isOffline),
      'searchedAt': serializer.toJson<DateTime>(searchedAt),
    };
  }

  SearchHistoryData copyWith(
          {int? id,
          String? query,
          String? title,
          Value<String?> subtitle = const Value.absent(),
          double? latitude,
          double? longitude,
          bool? isOffline,
          DateTime? searchedAt}) =>
      SearchHistoryData(
        id: id ?? this.id,
        query: query ?? this.query,
        title: title ?? this.title,
        subtitle: subtitle.present ? subtitle.value : this.subtitle,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        isOffline: isOffline ?? this.isOffline,
        searchedAt: searchedAt ?? this.searchedAt,
      );
  SearchHistoryData copyWithCompanion(SearchHistoryCompanion data) {
    return SearchHistoryData(
      id: data.id.present ? data.id.value : this.id,
      query: data.query.present ? data.query.value : this.query,
      title: data.title.present ? data.title.value : this.title,
      subtitle: data.subtitle.present ? data.subtitle.value : this.subtitle,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      isOffline: data.isOffline.present ? data.isOffline.value : this.isOffline,
      searchedAt:
          data.searchedAt.present ? data.searchedAt.value : this.searchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryData(')
          ..write('id: $id, ')
          ..write('query: $query, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('isOffline: $isOffline, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, query, title, subtitle, latitude, longitude, isOffline, searchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchHistoryData &&
          other.id == this.id &&
          other.query == this.query &&
          other.title == this.title &&
          other.subtitle == this.subtitle &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.isOffline == this.isOffline &&
          other.searchedAt == this.searchedAt);
}

class SearchHistoryCompanion extends UpdateCompanion<SearchHistoryData> {
  final Value<int> id;
  final Value<String> query;
  final Value<String> title;
  final Value<String?> subtitle;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<bool> isOffline;
  final Value<DateTime> searchedAt;
  const SearchHistoryCompanion({
    this.id = const Value.absent(),
    this.query = const Value.absent(),
    this.title = const Value.absent(),
    this.subtitle = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.isOffline = const Value.absent(),
    this.searchedAt = const Value.absent(),
  });
  SearchHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String query,
    required String title,
    this.subtitle = const Value.absent(),
    required double latitude,
    required double longitude,
    this.isOffline = const Value.absent(),
    this.searchedAt = const Value.absent(),
  })  : query = Value(query),
        title = Value(title),
        latitude = Value(latitude),
        longitude = Value(longitude);
  static Insertable<SearchHistoryData> custom({
    Expression<int>? id,
    Expression<String>? query,
    Expression<String>? title,
    Expression<String>? subtitle,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<bool>? isOffline,
    Expression<DateTime>? searchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (query != null) 'query': query,
      if (title != null) 'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (isOffline != null) 'is_offline': isOffline,
      if (searchedAt != null) 'searched_at': searchedAt,
    });
  }

  SearchHistoryCompanion copyWith(
      {Value<int>? id,
      Value<String>? query,
      Value<String>? title,
      Value<String?>? subtitle,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<bool>? isOffline,
      Value<DateTime>? searchedAt}) {
    return SearchHistoryCompanion(
      id: id ?? this.id,
      query: query ?? this.query,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isOffline: isOffline ?? this.isOffline,
      searchedAt: searchedAt ?? this.searchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subtitle.present) {
      map['subtitle'] = Variable<String>(subtitle.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (isOffline.present) {
      map['is_offline'] = Variable<bool>(isOffline.value);
    }
    if (searchedAt.present) {
      map['searched_at'] = Variable<DateTime>(searchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryCompanion(')
          ..write('id: $id, ')
          ..write('query: $query, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('isOffline: $isOffline, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SavedPlacesTable savedPlaces = $SavedPlacesTable(this);
  late final $RouteHistoryTable routeHistory = $RouteHistoryTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $LastKnownLocationTable lastKnownLocation =
      $LastKnownLocationTable(this);
  late final $SearchHistoryTable searchHistory = $SearchHistoryTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        savedPlaces,
        routeHistory,
        appSettings,
        lastKnownLocation,
        searchHistory
      ];
}

typedef $$SavedPlacesTableCreateCompanionBuilder = SavedPlacesCompanion
    Function({
  Value<int> id,
  required String name,
  required double latitude,
  required double longitude,
  Value<String?> address,
  Value<String> category,
  Value<DateTime> createdAt,
});
typedef $$SavedPlacesTableUpdateCompanionBuilder = SavedPlacesCompanion
    Function({
  Value<int> id,
  Value<String> name,
  Value<double> latitude,
  Value<double> longitude,
  Value<String?> address,
  Value<String> category,
  Value<DateTime> createdAt,
});

class $$SavedPlacesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$SavedPlacesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$SavedPlacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SavedPlacesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SavedPlacesTable,
    SavedPlace,
    $$SavedPlacesTableFilterComposer,
    $$SavedPlacesTableOrderingComposer,
    $$SavedPlacesTableAnnotationComposer,
    $$SavedPlacesTableCreateCompanionBuilder,
    $$SavedPlacesTableUpdateCompanionBuilder,
    (SavedPlace, BaseReferences<_$AppDatabase, $SavedPlacesTable, SavedPlace>),
    SavedPlace,
    PrefetchHooks Function()> {
  $$SavedPlacesTableTableManager(_$AppDatabase db, $SavedPlacesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedPlacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedPlacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedPlacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<String?> address = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              SavedPlacesCompanion(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            address: address,
            category: category,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            required double latitude,
            required double longitude,
            Value<String?> address = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              SavedPlacesCompanion.insert(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            address: address,
            category: category,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SavedPlacesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SavedPlacesTable,
    SavedPlace,
    $$SavedPlacesTableFilterComposer,
    $$SavedPlacesTableOrderingComposer,
    $$SavedPlacesTableAnnotationComposer,
    $$SavedPlacesTableCreateCompanionBuilder,
    $$SavedPlacesTableUpdateCompanionBuilder,
    (SavedPlace, BaseReferences<_$AppDatabase, $SavedPlacesTable, SavedPlace>),
    SavedPlace,
    PrefetchHooks Function()>;
typedef $$RouteHistoryTableCreateCompanionBuilder = RouteHistoryCompanion
    Function({
  Value<int> id,
  required double startLat,
  required double startLng,
  required double endLat,
  required double endLng,
  Value<String?> endLabel,
  Value<DateTime> createdAt,
});
typedef $$RouteHistoryTableUpdateCompanionBuilder = RouteHistoryCompanion
    Function({
  Value<int> id,
  Value<double> startLat,
  Value<double> startLng,
  Value<double> endLat,
  Value<double> endLng,
  Value<String?> endLabel,
  Value<DateTime> createdAt,
});

class $$RouteHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $RouteHistoryTable> {
  $$RouteHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get startLat => $composableBuilder(
      column: $table.startLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get startLng => $composableBuilder(
      column: $table.startLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get endLat => $composableBuilder(
      column: $table.endLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get endLng => $composableBuilder(
      column: $table.endLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get endLabel => $composableBuilder(
      column: $table.endLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$RouteHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $RouteHistoryTable> {
  $$RouteHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get startLat => $composableBuilder(
      column: $table.startLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get startLng => $composableBuilder(
      column: $table.startLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get endLat => $composableBuilder(
      column: $table.endLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get endLng => $composableBuilder(
      column: $table.endLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get endLabel => $composableBuilder(
      column: $table.endLabel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$RouteHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $RouteHistoryTable> {
  $$RouteHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get startLat =>
      $composableBuilder(column: $table.startLat, builder: (column) => column);

  GeneratedColumn<double> get startLng =>
      $composableBuilder(column: $table.startLng, builder: (column) => column);

  GeneratedColumn<double> get endLat =>
      $composableBuilder(column: $table.endLat, builder: (column) => column);

  GeneratedColumn<double> get endLng =>
      $composableBuilder(column: $table.endLng, builder: (column) => column);

  GeneratedColumn<String> get endLabel =>
      $composableBuilder(column: $table.endLabel, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$RouteHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RouteHistoryTable,
    RouteHistoryData,
    $$RouteHistoryTableFilterComposer,
    $$RouteHistoryTableOrderingComposer,
    $$RouteHistoryTableAnnotationComposer,
    $$RouteHistoryTableCreateCompanionBuilder,
    $$RouteHistoryTableUpdateCompanionBuilder,
    (
      RouteHistoryData,
      BaseReferences<_$AppDatabase, $RouteHistoryTable, RouteHistoryData>
    ),
    RouteHistoryData,
    PrefetchHooks Function()> {
  $$RouteHistoryTableTableManager(_$AppDatabase db, $RouteHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RouteHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RouteHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RouteHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<double> startLat = const Value.absent(),
            Value<double> startLng = const Value.absent(),
            Value<double> endLat = const Value.absent(),
            Value<double> endLng = const Value.absent(),
            Value<String?> endLabel = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              RouteHistoryCompanion(
            id: id,
            startLat: startLat,
            startLng: startLng,
            endLat: endLat,
            endLng: endLng,
            endLabel: endLabel,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required double startLat,
            required double startLng,
            required double endLat,
            required double endLng,
            Value<String?> endLabel = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              RouteHistoryCompanion.insert(
            id: id,
            startLat: startLat,
            startLng: startLng,
            endLat: endLat,
            endLng: endLng,
            endLabel: endLabel,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RouteHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RouteHistoryTable,
    RouteHistoryData,
    $$RouteHistoryTableFilterComposer,
    $$RouteHistoryTableOrderingComposer,
    $$RouteHistoryTableAnnotationComposer,
    $$RouteHistoryTableCreateCompanionBuilder,
    $$RouteHistoryTableUpdateCompanionBuilder,
    (
      RouteHistoryData,
      BaseReferences<_$AppDatabase, $RouteHistoryTable, RouteHistoryData>
    ),
    RouteHistoryData,
    PrefetchHooks Function()>;
typedef $$AppSettingsTableCreateCompanionBuilder = AppSettingsCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$AppSettingsTableUpdateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (AppSetting, BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>),
    AppSetting,
    PrefetchHooks Function()> {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppSettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (AppSetting, BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>),
    AppSetting,
    PrefetchHooks Function()>;
typedef $$LastKnownLocationTableCreateCompanionBuilder
    = LastKnownLocationCompanion Function({
  Value<int> id,
  required double latitude,
  required double longitude,
  Value<double?> heading,
  Value<double?> speedKmh,
  Value<double?> accuracy,
  Value<DateTime> updatedAt,
});
typedef $$LastKnownLocationTableUpdateCompanionBuilder
    = LastKnownLocationCompanion Function({
  Value<int> id,
  Value<double> latitude,
  Value<double> longitude,
  Value<double?> heading,
  Value<double?> speedKmh,
  Value<double?> accuracy,
  Value<DateTime> updatedAt,
});

class $$LastKnownLocationTableFilterComposer
    extends Composer<_$AppDatabase, $LastKnownLocationTable> {
  $$LastKnownLocationTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get heading => $composableBuilder(
      column: $table.heading, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get speedKmh => $composableBuilder(
      column: $table.speedKmh, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get accuracy => $composableBuilder(
      column: $table.accuracy, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LastKnownLocationTableOrderingComposer
    extends Composer<_$AppDatabase, $LastKnownLocationTable> {
  $$LastKnownLocationTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get heading => $composableBuilder(
      column: $table.heading, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get speedKmh => $composableBuilder(
      column: $table.speedKmh, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get accuracy => $composableBuilder(
      column: $table.accuracy, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LastKnownLocationTableAnnotationComposer
    extends Composer<_$AppDatabase, $LastKnownLocationTable> {
  $$LastKnownLocationTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get heading =>
      $composableBuilder(column: $table.heading, builder: (column) => column);

  GeneratedColumn<double> get speedKmh =>
      $composableBuilder(column: $table.speedKmh, builder: (column) => column);

  GeneratedColumn<double> get accuracy =>
      $composableBuilder(column: $table.accuracy, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LastKnownLocationTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LastKnownLocationTable,
    LastKnownLocationData,
    $$LastKnownLocationTableFilterComposer,
    $$LastKnownLocationTableOrderingComposer,
    $$LastKnownLocationTableAnnotationComposer,
    $$LastKnownLocationTableCreateCompanionBuilder,
    $$LastKnownLocationTableUpdateCompanionBuilder,
    (
      LastKnownLocationData,
      BaseReferences<_$AppDatabase, $LastKnownLocationTable,
          LastKnownLocationData>
    ),
    LastKnownLocationData,
    PrefetchHooks Function()> {
  $$LastKnownLocationTableTableManager(
      _$AppDatabase db, $LastKnownLocationTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LastKnownLocationTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LastKnownLocationTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LastKnownLocationTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<double?> heading = const Value.absent(),
            Value<double?> speedKmh = const Value.absent(),
            Value<double?> accuracy = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              LastKnownLocationCompanion(
            id: id,
            latitude: latitude,
            longitude: longitude,
            heading: heading,
            speedKmh: speedKmh,
            accuracy: accuracy,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required double latitude,
            required double longitude,
            Value<double?> heading = const Value.absent(),
            Value<double?> speedKmh = const Value.absent(),
            Value<double?> accuracy = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              LastKnownLocationCompanion.insert(
            id: id,
            latitude: latitude,
            longitude: longitude,
            heading: heading,
            speedKmh: speedKmh,
            accuracy: accuracy,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LastKnownLocationTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LastKnownLocationTable,
    LastKnownLocationData,
    $$LastKnownLocationTableFilterComposer,
    $$LastKnownLocationTableOrderingComposer,
    $$LastKnownLocationTableAnnotationComposer,
    $$LastKnownLocationTableCreateCompanionBuilder,
    $$LastKnownLocationTableUpdateCompanionBuilder,
    (
      LastKnownLocationData,
      BaseReferences<_$AppDatabase, $LastKnownLocationTable,
          LastKnownLocationData>
    ),
    LastKnownLocationData,
    PrefetchHooks Function()>;
typedef $$SearchHistoryTableCreateCompanionBuilder = SearchHistoryCompanion
    Function({
  Value<int> id,
  required String query,
  required String title,
  Value<String?> subtitle,
  required double latitude,
  required double longitude,
  Value<bool> isOffline,
  Value<DateTime> searchedAt,
});
typedef $$SearchHistoryTableUpdateCompanionBuilder = SearchHistoryCompanion
    Function({
  Value<int> id,
  Value<String> query,
  Value<String> title,
  Value<String?> subtitle,
  Value<double> latitude,
  Value<double> longitude,
  Value<bool> isOffline,
  Value<DateTime> searchedAt,
});

class $$SearchHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get query => $composableBuilder(
      column: $table.query, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subtitle => $composableBuilder(
      column: $table.subtitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isOffline => $composableBuilder(
      column: $table.isOffline, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => ColumnFilters(column));
}

class $$SearchHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get query => $composableBuilder(
      column: $table.query, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subtitle => $composableBuilder(
      column: $table.subtitle, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isOffline => $composableBuilder(
      column: $table.isOffline, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => ColumnOrderings(column));
}

class $$SearchHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get subtitle =>
      $composableBuilder(column: $table.subtitle, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<bool> get isOffline =>
      $composableBuilder(column: $table.isOffline, builder: (column) => column);

  GeneratedColumn<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => column);
}

class $$SearchHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SearchHistoryTable,
    SearchHistoryData,
    $$SearchHistoryTableFilterComposer,
    $$SearchHistoryTableOrderingComposer,
    $$SearchHistoryTableAnnotationComposer,
    $$SearchHistoryTableCreateCompanionBuilder,
    $$SearchHistoryTableUpdateCompanionBuilder,
    (
      SearchHistoryData,
      BaseReferences<_$AppDatabase, $SearchHistoryTable, SearchHistoryData>
    ),
    SearchHistoryData,
    PrefetchHooks Function()> {
  $$SearchHistoryTableTableManager(_$AppDatabase db, $SearchHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SearchHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SearchHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SearchHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> query = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> subtitle = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<bool> isOffline = const Value.absent(),
            Value<DateTime> searchedAt = const Value.absent(),
          }) =>
              SearchHistoryCompanion(
            id: id,
            query: query,
            title: title,
            subtitle: subtitle,
            latitude: latitude,
            longitude: longitude,
            isOffline: isOffline,
            searchedAt: searchedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String query,
            required String title,
            Value<String?> subtitle = const Value.absent(),
            required double latitude,
            required double longitude,
            Value<bool> isOffline = const Value.absent(),
            Value<DateTime> searchedAt = const Value.absent(),
          }) =>
              SearchHistoryCompanion.insert(
            id: id,
            query: query,
            title: title,
            subtitle: subtitle,
            latitude: latitude,
            longitude: longitude,
            isOffline: isOffline,
            searchedAt: searchedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SearchHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SearchHistoryTable,
    SearchHistoryData,
    $$SearchHistoryTableFilterComposer,
    $$SearchHistoryTableOrderingComposer,
    $$SearchHistoryTableAnnotationComposer,
    $$SearchHistoryTableCreateCompanionBuilder,
    $$SearchHistoryTableUpdateCompanionBuilder,
    (
      SearchHistoryData,
      BaseReferences<_$AppDatabase, $SearchHistoryTable, SearchHistoryData>
    ),
    SearchHistoryData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SavedPlacesTableTableManager get savedPlaces =>
      $$SavedPlacesTableTableManager(_db, _db.savedPlaces);
  $$RouteHistoryTableTableManager get routeHistory =>
      $$RouteHistoryTableTableManager(_db, _db.routeHistory);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$LastKnownLocationTableTableManager get lastKnownLocation =>
      $$LastKnownLocationTableTableManager(_db, _db.lastKnownLocation);
  $$SearchHistoryTableTableManager get searchHistory =>
      $$SearchHistoryTableTableManager(_db, _db.searchHistory);
}
