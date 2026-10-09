  const API = '/vulntrack/api';
  let token = sessionStorage.getItem('vulntrack_token');
  let mode = 'login';
  let currentFindings = [];
  let sortKey = null;
  let sortDir = 1;

  const authScreen = document.getElementById('authScreen');
  const dashboard = document.getElementById('dashboard');
  const topbar = document.getElementById('topbar');
  const authForm = document.getElementById('authForm');
  const authError = document.getElementById('authError');
  const authTitle = document.getElementById('authTitle');
  const authSub = document.getElementById('authSub');
  const authSubmit = document.getElementById('authSubmit');
  const authToggle = document.getElementById('authToggle');
  const statsRow = document.getElementById('statsRow');

  function decodeRole(jwt) {
    try {
      const payload = JSON.parse(atob(jwt.split('.')[1]));
      return { username: payload.sub, role: payload.role };
    } catch (e) {
      return { username: '', role: '' };
    }
  }

  function showBanner(msg, type) {
    authError.textContent = msg;
    authError.className = 'banner ' + (type || 'error');
    authError.hidden = false;
  }

  function setMode(next) {
    mode = next;
    authError.hidden = true;
    authForm.reset();
    if (mode === 'login') {
      authTitle.textContent = 'Log in';
      authSub.textContent = 'Access your findings dashboard.';
      authSubmit.textContent = 'Log in';
      authToggle.innerHTML = 'Need an account? <a id="toggleLink">Register</a>';
    } else {
      authTitle.textContent = 'Register';
      authSub.textContent = 'Create an analyst account.';
      authSubmit.textContent = 'Create account';
      authToggle.innerHTML = 'Already have an account? <a id="toggleLink">Log in</a>';
    }
    document.getElementById('toggleLink').addEventListener('click', () => setMode(mode === 'login' ? 'register' : 'login'));
  }
  document.getElementById('toggleLink').addEventListener('click', () => setMode('register'));

  authForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    authError.hidden = true;
    const username = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value;
    authSubmit.disabled = true;

    try {
      if (mode === 'register') {
        const res = await fetch(`${API}/auth/register`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ username, password, role: 'ANALYST' })
        });
        if (!res.ok) { showBanner('Could not create that account. Try a different username.', 'error'); authSubmit.disabled = false; return; }
        setMode('login');
        showBanner('Account created — log in below.', 'success');
        authSubmit.disabled = false;
        return;
      }

      const res = await fetch(`${API}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password })
      });
      if (!res.ok) { showBanner('Incorrect username or password.', 'error'); authSubmit.disabled = false; return; }
      const data = await res.json();
      token = data.token;
      sessionStorage.setItem('vulntrack_token', token);
      enterDashboard();
    } catch (err) {
      showBanner('Could not reach the server. Is the API running?', 'error');
      authSubmit.disabled = false;
    }
  });

  document.getElementById('logoutBtn').addEventListener('click', logoutSilently);
  document.getElementById('refreshBtn').addEventListener('click', () => loadFindings());

  function severityBadge(sev) {
    if (!sev) return '';
    return `<span class="badge sev-${sev}">${sev}</span>`;
  }

  function statusLabel(st) {
    if (!st) return '';
    return `<span class="st-${st}">${st.replace('_', ' ')}</span>`;
  }

  function updateStats(findings) {
    const counts = { CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 0 };
    findings.forEach(f => {
      const sev = f.vulnerability ? f.vulnerability.severity : null;
      if (sev && counts.hasOwnProperty(sev)) counts[sev]++;
    });
    document.getElementById('statTotal').textContent = findings.length;
    document.getElementById('statCritical').textContent = counts.CRITICAL;
    document.getElementById('statHigh').textContent = counts.HIGH;
    document.getElementById('statMedium').textContent = counts.MEDIUM;
    document.getElementById('statLow').textContent = counts.LOW;
  }

  const sevRank = { CRITICAL: 4, HIGH: 3, MEDIUM: 2, LOW: 1 };

  function sortFindings(findings) {
    if (!sortKey) return findings;
    const sorted = [...findings].sort((a, b) => {
      let av, bv;
      if (sortKey === 'asset') { av = a.asset ? a.asset.hostname : ''; bv = b.asset ? b.asset.hostname : ''; }
      else if (sortKey === 'cve') { av = a.vulnerability ? a.vulnerability.cveId : ''; bv = b.vulnerability ? b.vulnerability.cveId : ''; }
      else if (sortKey === 'severity') { av = sevRank[a.vulnerability ? a.vulnerability.severity : ''] || 0; bv = sevRank[b.vulnerability ? b.vulnerability.severity : ''] || 0; }
      else if (sortKey === 'status') { av = a.status || ''; bv = b.status || ''; }
      else if (sortKey === 'deadline') { av = a.remediationDeadline || ''; bv = b.remediationDeadline || ''; }
      else { av = ''; bv = ''; }
      if (av < bv) return -1 * sortDir;
      if (av > bv) return 1 * sortDir;
      return 0;
    });
    return sorted;
  }

  function renderTable() {
    const container = document.getElementById('findingsContainer');
    const findings = sortFindings(currentFindings);

    const arrow = (key) => sortKey === key ? `<span class="sort-arrow">${sortDir === 1 ? '\u25B2' : '\u25BC'}</span>` : '';

    const rows = findings.map(f => `
      <tr>
        <td>${f.asset ? f.asset.hostname : '\u2014'}</td>
        <td class="mono">${f.vulnerability ? f.vulnerability.cveId : '\u2014'}</td>
        <td>${severityBadge(f.vulnerability ? f.vulnerability.severity : null)}</td>
        <td>${statusLabel(f.status)}</td>
        <td>${f.remediationDeadline || '\u2014'}</td>
        <td>${f.assignedUser ? f.assignedUser.username : 'Unassigned'}</td>
      </tr>
    `).join('');

    container.innerHTML = `
      <table>
        <thead>
          <tr>
            <th class="sortable" data-key="asset" tabindex="0">Asset ${arrow('asset')}</th>
            <th class="sortable" data-key="cve" tabindex="0">CVE ${arrow('cve')}</th>
            <th class="sortable" data-key="severity" tabindex="0">Severity ${arrow('severity')}</th>
            <th class="sortable" data-key="status" tabindex="0">Status ${arrow('status')}</th>
            <th class="sortable" data-key="deadline" tabindex="0">Deadline ${arrow('deadline')}</th>
            <th>Assigned to</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>`;

    container.querySelectorAll('th.sortable').forEach(th => {
      const handler = () => {
        const key = th.dataset.key;
        if (sortKey === key) { sortDir *= -1; } else { sortKey = key; sortDir = 1; }
        renderTable();
      };
      th.addEventListener('click', handler);
      th.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handler(); } });
    });
  }

  function renderSkeleton() {
    const container = document.getElementById('findingsContainer');
    const skeletonRows = Array.from({ length: 3 }).map(() => `
      <tr class="skeleton-row">
        <td><div class="skeleton-bar" style="width:70%"></div></td>
        <td><div class="skeleton-bar" style="width:80%"></div></td>
        <td><div class="skeleton-bar" style="width:50%"></div></td>
        <td><div class="skeleton-bar" style="width:60%"></div></td>
        <td><div class="skeleton-bar" style="width:55%"></div></td>
        <td><div class="skeleton-bar" style="width:65%"></div></td>
      </tr>`).join('');
    container.innerHTML = `
      <table>
        <thead>
          <tr><th>Asset</th><th>CVE</th><th>Severity</th><th>Status</th><th>Deadline</th><th>Assigned to</th></tr>
        </thead>
        <tbody>${skeletonRows}</tbody>
      </table>`;
  }

  function setLastUpdated() {
    const now = new Date();
    document.getElementById('lastUpdated').textContent = 'Updated ' + now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  async function loadFindings() {
    const container = document.getElementById('findingsContainer');
    const refreshBtn = document.getElementById('refreshBtn');
    refreshBtn.disabled = true;
    renderSkeleton();

    try {
      const res = await fetch(`${API}/findings`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (res.status === 401) { logoutSilently(); return; }
      const findings = await res.json();
      currentFindings = findings;
      statsRow.hidden = findings.length === 0;

      if (findings.length === 0) {
        container.innerHTML = `
          <div class="empty-state">
            <div class="glyph">&#9678;</div>
            <p>No findings yet</p>
            <p>Findings created via the API will appear here.</p>
          </div>`;
      } else {
        updateStats(findings);
        renderTable();
      }
      setLastUpdated();
    } catch (err) {
      container.innerHTML = `<div class="empty-state"><p>Could not load findings</p><p>Check that the API is reachable.</p></div>`;
    } finally {
      refreshBtn.disabled = false;
    }
  }

  function logoutSilently() {
    sessionStorage.removeItem('vulntrack_token');
    token = null;
    dashboard.hidden = true;
    topbar.hidden = true;
    authScreen.hidden = false;
    setMode('login');
  }

  function enterDashboard() {
    const { username, role } = decodeRole(token);
    document.getElementById('userLabel').textContent = username;
    document.getElementById('roleLabel').textContent = role;
    authScreen.hidden = true;
    topbar.hidden = false;
    dashboard.hidden = false;
    loadFindings();
  }

  setMode('login');
  if (token) enterDashboard();
