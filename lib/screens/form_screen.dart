import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// Fills AcroForm fields of a PDF: reads the fields, shows editors per kind,
/// writes a filled copy. Choice/list fields take the export value as text.
class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  File? _input;
  List<PdfFormField> _fields = const [];
  final _textControllers = <String, TextEditingController>{};
  final _boolValues = <String, bool>{};
  bool _running = false;
  File? _output;
  String? _error;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    final f = files.first;
    setState(() {
      _input = f;
      _fields = const [];
      _output = null;
      _error = null;
      _textControllers.clear();
      _boolValues.clear();
    });
    try {
      final fields = await PdfEngine.instance.formFields(f);
      for (final field in fields) {
        if (field.value case PdfTextValue(:final text)) {
          _textControllers[field.name] = TextEditingController(text: text);
        } else if (field.value case PdfCheckedValue(:final isChecked)) {
          _boolValues[field.name] = isChecked;
        } else {
          _textControllers[field.name] = TextEditingController();
        }
      }
      setState(() => _fields = fields);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null) return;
    final values = <String, PdfFormFieldValue>{};
    for (final field in _fields) {
      if (field.isReadOnly) continue;
      switch (field.kind) {
        case PdfFormFieldKind.textField:
          values[field.name] = PdfFormFieldValue.text(
            _textControllers[field.name]!.text,
          );
        case PdfFormFieldKind.checkbox:
          values[field.name] = PdfFormFieldValue.checked(
            _boolValues[field.name] ?? false,
          );
        case PdfFormFieldKind.comboBox:
        case PdfFormFieldKind.listBox:
        case PdfFormFieldKind.radioGroup:
          final text = _textControllers[field.name]!.text.trim();
          values[field.name] = text.isEmpty
              ? PdfFormFieldValue.none()
              : PdfFormFieldValue.choice(text);
        default:
          break;
      }
    }
    if (values.isEmpty) {
      setState(() => _error = 'Không có field nào để điền');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final out = await outputFile(
        '${fileBaseName(input.path)}_dien',
        'pdf',
      );
      await PdfEngine.instance.fillForm(input, out, values);
      setState(() => _output = out);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Điền form PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.assignment_outlined,
            label: 'Chọn PDF có form',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
            trailing: _fields.isNotEmpty
                ? Chip(label: Text('${_fields.length} field'))
                : null,
          ),
          if (_input != null && _fields.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('File không có form field nào.'),
            ),
          for (final field in _fields) _fieldEditor(field),
          if (_fields.isNotEmpty) ...[
            const SizedBox(height: 12),
            RunButton(
              label: 'Điền & xuất PDF',
              onPressed: _run,
              enabled: !_running,
            ),
          ],
          const SizedBox(height: 16),
          if (_running) const RunningPane(message: 'Đang điền form…'),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }

  Widget _fieldEditor(PdfFormField field) {
    final subtitle = [
      field.tooltip,
      if (field.isRequired) 'bắt buộc',
      if (field.isReadOnly) 'chỉ đọc',
    ].whereType<String>().join(' · ');
    switch (field.kind) {
      case PdfFormFieldKind.checkbox:
        return SwitchListTile(
          title: Text(field.name),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          value: _boolValues[field.name] ?? false,
          onChanged: field.isReadOnly
              ? null
              : (v) => setState(() => _boolValues[field.name] = v),
        );
      case PdfFormFieldKind.pushButton:
      case PdfFormFieldKind.signatureField:
      case PdfFormFieldKind.unknown:
        return ListTile(
          dense: true,
          leading: const Icon(Icons.lock_outline),
          title: Text(field.name),
          subtitle: Text('${field.kind.wire} — không điền được'),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _textControllers[field.name],
            enabled: !field.isReadOnly,
            maxLength: field.maxLength,
            decoration: InputDecoration(
              labelText: field.name,
              helperText: [
                field.kind.wire,
                if (subtitle.isNotEmpty) subtitle,
              ].join(' · '),
            ),
          ),
        );
    }
  }
}
