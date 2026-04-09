/// A tunable parameter exposed to the agent.
///
/// Each parameter has a name, bounds, current value, and type.
class TunableParameter {
  final String name;
  final String description;
  final double minValue;
  final double maxValue;
  final double currentValue;
  final double defaultValue;
  final ParameterScope scope;
  final ParameterType type;

  const TunableParameter({
    required this.name,
    required this.description,
    required this.minValue,
    required this.maxValue,
    required this.currentValue,
    required this.defaultValue,
    this.scope = ParameterScope.global,
    this.type = ParameterType.continuous,
  });

  TunableParameter withValue(double newValue) {
    return TunableParameter(
      name: name,
      description: description,
      minValue: minValue,
      maxValue: maxValue,
      currentValue: newValue.clamp(minValue, maxValue),
      defaultValue: defaultValue,
      scope: scope,
      type: type,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'description': description,
    'min': minValue,
    'max': maxValue,
    'current': currentValue,
    'default': defaultValue,
    'scope': scope.name,
    'type': type.name,
  };
}

enum ParameterScope { global, perIsland }

enum ParameterType { continuous, integer, boolean }

/// Registry of all tunable parameters.
class ParameterRegistry {
  final Map<String, TunableParameter> _params = {};

  void register(TunableParameter param) {
    _params[param.name] = param;
  }

  TunableParameter? get(String name) => _params[name];

  bool update(String name, double value) {
    final param = _params[name];
    if (param == null) return false;
    _params[name] = param.withValue(value);
    return true;
  }

  List<TunableParameter> get all => _params.values.toList();

  Map<String, double> get currentValues =>
      _params.map((k, v) => MapEntry(k, v.currentValue));

  /// Initialize with all DE parameters.
  void registerDefaults() {
    register(
      const TunableParameter(
        name: 'mutationFactor',
        description: 'DE scaling factor F',
        minValue: 0.0,
        maxValue: 2.0,
        currentValue: 0.5,
        defaultValue: 0.5,
      ),
    );
    register(
      const TunableParameter(
        name: 'crossoverRate',
        description: 'DE crossover rate CR',
        minValue: 0.0,
        maxValue: 1.0,
        currentValue: 0.9,
        defaultValue: 0.9,
      ),
    );
    register(
      const TunableParameter(
        name: 'populationSize',
        description: 'Population size per island',
        minValue: 20,
        maxValue: 500,
        currentValue: 50,
        defaultValue: 50,
        type: ParameterType.integer,
      ),
    );
    register(
      const TunableParameter(
        name: 'elitismCount',
        description: 'Number of elite individuals preserved',
        minValue: 0,
        maxValue: 20,
        currentValue: 2,
        defaultValue: 2,
        type: ParameterType.integer,
      ),
    );
    register(
      const TunableParameter(
        name: 'migrationInterval',
        description: 'Generations between migrations',
        minValue: 5,
        maxValue: 100,
        currentValue: 20,
        defaultValue: 20,
        type: ParameterType.integer,
      ),
    );
    register(
      const TunableParameter(
        name: 'migrationRate',
        description: 'Fraction of population to migrate',
        minValue: 0.0,
        maxValue: 0.3,
        currentValue: 0.1,
        defaultValue: 0.1,
      ),
    );
    register(
      const TunableParameter(
        name: 'maxRegressors',
        description: 'Maximum regressors per model',
        minValue: 2,
        maxValue: 20,
        currentValue: 8,
        defaultValue: 8,
        type: ParameterType.integer,
      ),
    );
    register(
      const TunableParameter(
        name: 'maxExponent',
        description: 'Maximum exponent value',
        minValue: 1,
        maxValue: 5,
        currentValue: 3,
        defaultValue: 3,
      ),
    );
    register(
      const TunableParameter(
        name: 'maxDelay',
        description: 'Maximum time delay',
        minValue: 1,
        maxValue: 50,
        currentValue: 20,
        defaultValue: 20,
        type: ParameterType.integer,
      ),
    );
    register(
      const TunableParameter(
        name: 'complexityPenalty',
        description: 'Weight for complexity penalty in fitness',
        minValue: 0.0,
        maxValue: 10.0,
        currentValue: 1.0,
        defaultValue: 1.0,
      ),
    );
    register(
      const TunableParameter(
        name: 'stagnationLimit',
        description: 'Generations without improvement before stop',
        minValue: 50,
        maxValue: 5000,
        currentValue: 500,
        defaultValue: 500,
        type: ParameterType.integer,
      ),
    );
    register(
      const TunableParameter(
        name: 'reinitializationRatio',
        description: 'Fraction of worst to reinitialize on stagnation',
        minValue: 0.0,
        maxValue: 0.5,
        currentValue: 0.1,
        defaultValue: 0.1,
      ),
    );
  }
}

/// A tuning action applied by the agent.
class TuningAction {
  final String parameterName;
  final double oldValue;
  final double newValue;
  final int generation;
  final String? reason;

  const TuningAction({
    required this.parameterName,
    required this.oldValue,
    required this.newValue,
    required this.generation,
    this.reason,
  });

  Map<String, dynamic> toMap() => {
    'parameter': parameterName,
    'oldValue': oldValue,
    'newValue': newValue,
    'generation': generation,
    'reason': reason,
  };
}
