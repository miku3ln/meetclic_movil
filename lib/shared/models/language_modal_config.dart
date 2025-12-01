import 'package:flutter/material.dart';
import 'package:meetclic_movil/domain/entities/menu_tab_up_item.dart';

class LanguageModalConfig {
  final BuildContext context;
  final Function(String) onChanged;
  final List<MenuTabUpItem> menuTabUpItems;
  final void Function(VoidCallback fn) setStateFn;

  LanguageModalConfig({
    required this.context,
    required this.onChanged,
    required this.menuTabUpItems,
    required this.setStateFn,
  });
}
