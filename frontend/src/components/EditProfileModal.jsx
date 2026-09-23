import React, { useState, useEffect } from 'react';
import Modal from './Modal';
import { useAuth } from '../context/AuthContext';
import { updateProfile, UPLOADS_URL } from '../services/api';

const EditProfileModal = ({ isOpen, onClose }) => {
  const { user, refreshUser } = useAuth();
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [profileImage, setProfileImage] = useState(null);
  const [imagePreview, setImagePreview] = useState('');
  const [existingImage, setExistingImage] = useState('');
  const [success, setSuccess] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (isOpen && user) {
      setName(user.name || '');
      setPhone(user.phone || '');
      setExistingImage(user.profile_image ? `${UPLOADS_URL}/${user.profile_image}` : '');
      setProfileImage(null);
      setImagePreview('');
      setSuccess('');
      setError('');
    }
  }, [isOpen, user]);

  const handleImageChange = (e) => {
    const file = e.target.files[0];
    setProfileImage(file || null);
    if (!profileImage) {
      setImagePreview(file ? URL.createObjectURL(file) : '');
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setSuccess('');
    setLoading(true);

    try {
      const payload = new FormData();
      payload.append('name', name);
      payload.append('phone', phone);
      if (profileImage) payload.append('profile_image', profileImage);

      await updateProfile(payload);
      await refreshUser();
      setSuccess('Profile updated successfully');
      setTimeout(onClose, 1200);
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to update profile');
    } finally {
      setLoading(false);
    }
  };

  const previewSrc = imagePreview || existingImage;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Edit Profile">
      {success && <div style={styles.success} data-test="profile-success-message">{success}</div>}
      {error && <div style={styles.error} data-test="profile-error-message">{error}</div>}
      <form onSubmit={handleSubmit}>
        <div style={styles.avatarSection}>
          {previewSrc ? (
            <img src={previewSrc} alt="Profile preview" style={styles.avatarImage} data-test="profile-image-preview" />
          ) : (
            <div style={styles.avatar} data-test="profile-avatar-initial">
              {user?.name?.charAt(0).toUpperCase()}
            </div>
          )}
        </div>
        <div style={styles.inputGroup}>
          <label style={styles.label}>Full Name</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="John Doe"
            style={styles.input}
            data-test="profile-name-input"
            required
          />
        </div>
        <div style={styles.inputGroup}>
          <label style={styles.label}>Phone Number</label>
          <input
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="+1234567890"
            style={styles.input}
            data-test="profile-phone-input"
            required
          />
        </div>
        <div style={styles.inputGroup}>
          <label style={styles.label}>Profile Image</label>
          <input
            type="file"
            accept="image/*"
            onChange={handleImageChange}
            style={styles.input}
            data-test="profile-image-input"
          />
        </div>
        <div style={styles.buttonGroup}>
          <button type="button" onClick={onClose} style={styles.cancelBtn} data-test="profile-cancel-button">
            Cancel
          </button>
          <button type="submit" style={styles.submitBtn} disabled={loading} data-test="profile-save-button">
            {loading ? 'Saving...' : 'Save Changes'}
          </button>
        </div>
      </form>
    </Modal>
  );
};

const styles = {
  avatarSection: {
    display: 'flex',
    justifyContent: 'center',
    marginBottom: '20px',
  },
  avatarImage: {
    width: '100px',
    height: '100px',
    borderRadius: '50%',
    objectFit: 'cover',
    border: '1px solid #ddd',
  },
  avatar: {
    width: '100px',
    height: '100px',
    borderRadius: '50%',
    backgroundColor: '#007bff',
    color: 'white',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    fontSize: '40px',
    fontWeight: 'bold',
  },
  inputGroup: {
    marginBottom: '16px',
  },
  label: {
    display: 'block',
    marginBottom: '5px',
    color: '#555',
    fontSize: '14px',
  },
  input: {
    width: '100%',
    padding: '10px',
    border: '1px solid #ddd',
    borderRadius: '4px',
    fontSize: '14px',
    boxSizing: 'border-box',
  },
  buttonGroup: {
    display: 'flex',
    justifyContent: 'flex-end',
    gap: '10px',
    marginTop: '20px',
    paddingTop: '16px',
    borderTop: '1px solid #eee',
  },
  cancelBtn: {
    padding: '10px 20px',
    backgroundColor: '#6c757d',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '14px',
  },
  submitBtn: {
    padding: '10px 20px',
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '14px',
  },
  success: {
    backgroundColor: '#d4edda',
    color: '#155724',
    padding: '10px',
    borderRadius: '4px',
    marginBottom: '16px',
    textAlign: 'center',
  },
  error: {
    backgroundColor: '#ffe6e6',
    color: '#cc0000',
    padding: '10px',
    borderRadius: '4px',
    marginBottom: '16px',
    textAlign: 'center',
  },
};

export default EditProfileModal;