// Nova Companion: reports VS Code activity to Nova's local socket as
// newline-delimited JSON. If Nova isn't running, events are dropped silently.
const vscode = require('vscode');
const net = require('net');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const SOCKET = process.env.NOVA_SOCKET ||
  path.join(os.homedir(), 'Library', 'Application Support', 'Nova', 'nova.sock');

let sessionId = '';
let lastErrorCount = 0;

function workspaceDir() {
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return folder ? folder.uri.fsPath : undefined;
}

function send(event, fields = {}) {
  const payload = JSON.stringify({
    agent: 'vscode', sessionId, event, host: 'vscode',
    workingDirectory: workspaceDir(), ...fields,
  }) + '\n';
  const socket = net.createConnection(SOCKET);
  socket.on('error', () => {});            // Nova not running: ignore.
  socket.setTimeout(1000, () => socket.destroy());
  socket.end(payload);
}

function debounce(fn, ms) {
  let timer;
  return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), ms); };
}

function activate(context) {
  const seed = (workspaceDir() || 'no-folder') + ':' + process.pid;
  sessionId = 'vscode-' + crypto.createHash('sha1').update(seed).digest('hex').slice(0, 12);
  send('session_start', { description: vscode.workspace.name || 'VS Code' });

  const sub = (d) => context.subscriptions.push(d);

  sub(vscode.window.onDidChangeActiveTextEditor(debounce((editor) => {
    if (!editor || editor.document.uri.scheme !== 'file') return;
    const file = editor.document.fileName;
    send('tool_start', { tool: 'Read', description: 'Viewing ' + path.basename(file), filePath: file });
    send('tool_end', { tool: 'Read' });
  }, 1500)));

  sub(vscode.workspace.onDidSaveTextDocument((doc) => {
    if (doc.uri.scheme !== 'file') return;
    send('tool_start', { tool: 'Edit', description: 'Saved ' + path.basename(doc.fileName), filePath: doc.fileName });
    send('tool_end', { tool: 'Edit' });
  }));

  sub(vscode.tasks.onDidStartTaskProcess((e) => {
    send('tool_start', { tool: 'Task', description: 'Running task ' + e.execution.task.name, command: e.execution.task.name });
  }));
  sub(vscode.tasks.onDidEndTaskProcess((e) => {
    const failed = typeof e.exitCode === 'number' && e.exitCode !== 0;
    send(failed ? 'tool_failed' : 'tool_end', { tool: 'Task', description: e.execution.task.name + (failed ? ' failed (' + e.exitCode + ')' : ' finished') });
  }));

  sub(vscode.debug.onDidStartDebugSession((s) => {
    send('tool_start', { tool: 'Debug', description: 'Debugging ' + s.name });
  }));
  sub(vscode.debug.onDidTerminateDebugSession(() => send('tool_end', { tool: 'Debug' })));

  sub(vscode.languages.onDidChangeDiagnostics(debounce(() => {
    let errors = 0;
    for (const [, list] of vscode.languages.getDiagnostics()) {
      errors += list.filter((d) => d.severity === vscode.DiagnosticSeverity.Error).length;
    }
    if (errors > lastErrorCount && errors > 0) {
      send('notification', { message: errors + ' error' + (errors === 1 ? '' : 's') + ' in ' + (vscode.workspace.name || 'workspace') });
    }
    lastErrorCount = errors;
  }, 3000)));
}

function deactivate() {
  send('stop');
}

module.exports = { activate, deactivate };
