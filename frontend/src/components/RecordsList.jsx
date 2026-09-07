import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { getRecords, deleteRecord, UPLOADS_URL } from '../services/api';
import RecordFormModal from './RecordFormModal';
import BrandHeader from './BrandHeader';

const RecordsList = () => {
  const [records, setRecords] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editingRecord, setEditingRecord] = useState(null);
  const { user, isAdmin } = useAuth();
  const navigate = useNavigate();

  const loadRecords = useCallback(async () => {
    try {
      setLoading(true);
      const data = await getRecords();
      setRecords(data.records);
    } catch (err) {
      setError('Failed to load records');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadRecords();
  }, [loadRecords]);

  const handleDelete = async (id) => {
    if (!window.confirm('Are you sure you want to delete this record?')) return;
    try {
      await deleteRecord(id);
      loadRecords();
    } catch (err) {
      setError('Failed to delete record');
    }
  };

  const handleEdit = (record) => {
    setEditingRecord(record);
    setModalOpen(true);
  };

  const handleCreate = () => {
    setEditingRecord(null);
    setModalOpen(true);
  };

  const handleModalClose = () => {
    setModalOpen(false);
    setEditingRecord(null);
  };

  const handleSaved = () => {
    setModalOpen(false);
    setEditingRecord(null);
    loadRecords();
  };

  return (
    <div style={styles.page}>
      <BrandHeader />
      <div style={styles.body}>
      <div style={styles.container}>
        <div style={styles.header}>
          <div>
            <h2 style={styles.title}>Records</h2>
            <p style={styles.subtitle}>
              {isAdmin ? 'Viewing all records' : 'Your records'}
            </p>
          </div>
          <div style={styles.headerActions}>
            <button onClick={() => navigate('/dashboard')} style={styles.backBtn}>
              Dashboard
            </button>
            <button onClick={handleCreate} style={styles.addBtn}>
              + Add Record
            </button>
          </div>
        </div>

        {error && <div style={styles.error}>{error}</div>}

        {loading ? (
          <div style={styles.loading}>Loading records...</div>
        ) : records.length === 0 ? (
          <div style={styles.empty}>
            <p>No records found.</p>
            <button onClick={handleCreate} style={styles.addBtn}>Create your first record</button>
          </div>
        ) : (
          <div style={styles.tableWrapper}>
            <table style={styles.table}>
              <thead>
                <tr>
                  <th style={styles.th}>First Name</th>
                  <th style={styles.th}>Last Name</th>
                  <th style={styles.th}>Email</th>
                  <th style={styles.th}>Location</th>
                  <th style={styles.th}>Profile</th>
                  {isAdmin && <th style={styles.th}>Created By</th>}
                  <th style={{ ...styles.th, textAlign: 'center' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {records.map((record) => (
                  <tr key={record.id} style={styles.tr}>
                    <td style={styles.td}>{record.first_name}</td>
                    <td style={styles.td}>{record.last_name}</td>
                    <td style={styles.td}>{record.email_address}</td>
                    <td style={{ ...styles.td, fontSize: '12px' }}>{record.location || '-'}</td>
                    <td style={styles.td}>
                      {record.profile_image ? (
                        <img
                          src={`${UPLOADS_URL}/${record.profile_image}`}
                          alt={`${record.first_name} ${record.last_name}`}
                          style={styles.thumbnail}
                        />
                      ) : (
                        '-'
                      )}
                    </td>
                    {isAdmin && <td style={styles.td}>{record.created_by_name}</td>}
                    <td style={{ ...styles.td, textAlign: 'center' }}>
                      <button
                        onClick={() => handleEdit(record)}
                        style={styles.editBtn}
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => handleDelete(record.id)}
                        style={styles.deleteBtn}
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      </div>

      <RecordFormModal
        isOpen={modalOpen}
        onClose={handleModalClose}
        record={editingRecord}
        onSaved={handleSaved}
      />
    </div>
  );
};

const styles = {
  page: {
    minHeight: '100vh',
    backgroundColor: '#f5f5f5',
  },
  body: {
    padding: '20px',
  },
  container: {
    maxWidth: '900px',
    margin: '0 auto',
    backgroundColor: 'white',
    borderRadius: '8px',
    boxShadow: '0 2px 10px rgba(0,0,0,0.1)',
    padding: '24px',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: '24px',
  },
  headerActions: {
    display: 'flex',
    gap: '8px',
  },
  title: {
    margin: '0 0 4px',
    color: '#333',
    fontSize: '22px',
  },
  subtitle: {
    margin: 0,
    color: '#999',
    fontSize: '13px',
  },
  addBtn: {
    padding: '8px 16px',
    backgroundColor: '#28a745',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '14px',
  },
  backBtn: {
    padding: '8px 16px',
    backgroundColor: '#6c757d',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '14px',
  },
  error: {
    backgroundColor: '#ffe6e6',
    color: '#cc0000',
    padding: '10px',
    borderRadius: '4px',
    marginBottom: '16px',
  },
  loading: {
    textAlign: 'center',
    padding: '40px',
    color: '#999',
  },
  empty: {
    textAlign: 'center',
    padding: '40px',
    color: '#999',
  },
  tableWrapper: {
    overflowX: 'auto',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
  },
  th: {
    textAlign: 'left',
    padding: '12px 10px',
    borderBottom: '2px solid #ddd',
    fontSize: '13px',
    color: '#555',
    fontWeight: 'bold',
  },
  tr: {
    borderBottom: '1px solid #eee',
  },
  td: {
    padding: '10px',
    fontSize: '14px',
    color: '#333',
  },
  thumbnail: {
    width: '40px',
    height: '40px',
    objectFit: 'cover',
    borderRadius: '50%',
    border: '1px solid #ddd',
  },
  editBtn: {
    padding: '5px 10px',
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '12px',
    marginRight: '5px',
  },
  deleteBtn: {
    padding: '5px 10px',
    backgroundColor: '#dc3545',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '12px',
  },
};

export default RecordsList;
